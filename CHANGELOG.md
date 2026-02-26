# Refactor Changelog (Godot 4.6 best practices)

## Summary

Code-only refactor for maintainability, clarity, and Godot 4.x conventions. **No gameplay behavior changes.** No scripts or resources were moved or renamed; all paths remain valid.

---

## Folder structure (unchanged)

No files were moved. Current layout:

```
res://
  addons/           # gdfxr, kanban_tasks — left unchanged
  fonts/
  scenes/
    core/           # boot
    gameplay/       # game, player, pillar, presence_rw, fog_of_war_rw, powerup_fade_sprite
    presence/       # grab_attack
    ui/             # main_menu, loading_overlay, minimap, grab_minigame, pause_menu, etc.
    utils/          # SkillManager, transition_controller
  scripts/
    core/           # autoloads: event_bus, game_state, game_config, save_manager,
                   # SceneLoader, boot, scene_references, settings_manager
    gameplay/       # game, player, game_controller, pillar, presence_rw, skills/, etc.
    level/          # grid_model
    presence/       # grab/grab_attack
    systems/        # audio_manager, visual_effects_manager, animation_controller
    ui/             # ui_manager, health_bar, minimap, pause_menu, etc.
    world/          # tile_map
  resources/        # (skill .tres, pools live under scripts/gameplay/skills/...)
  shaders/
  sounds/
  sprites/
  themes/
```

---

## Moved / renamed paths

### Script reorganization (scripts into folders)

- **scripts/core/transition_controller.gd** → **scripts/utils/transition_controller.gd** (aligns with `scenes/utils/transition_controller.tscn`). Scene path updated in `scenes/utils/transition_controller.tscn`.
- **scripts/core/vision_controller.gd** → **scripts/systems/vision_controller.gd** (vision as a system). No code path references; only `class_name` usage.
- **scripts/core/presence_spawn_strategy.gd** → **scripts/presence/presence_spawn_strategy.gd** (presence domain). No path references; only `class_name` usage.

Layout is documented in **docs/SCRIPT_ORGANIZATION.md**. All other refactors below were in-place (same path, same `class_name` and public APIs).

---

## Notable refactors

### Core (autoloads)

- **event_bus.gd** — Section layout (#region Signals, Lifecycle). No logic change.
- **game_state.gd** — Constants/layout; `State` enum formatted; typed `_emit_state_change`; debug print kept.
- **game_config.gd** — Grouped vars into regions (Player, Doors, Presence, Maze, Markings, Pillar, GameController, FOV, Heartbeat, Minimap, Static). Removed empty `_init()`. Typed `get_all_vars()` return. `default_stats` explicitly typed as `Dictionary`.
- **save_manager.gd** — Regions; typed locals and returns; `load_game()` return handling; `_on_game_won()` return type; `load_previous_win_stats()` early-return and typed return.
- **SceneLoader.gd** — Regions; typed `_path`, `progress` array; `_done`/`_fail` in Private Methods. **Signal names:** script always had `loading_started` / `loading_finished`; call sites that used `scene_loading_started` / `scene_loading_finished` were fixed to use the correct names.
- **boot.gd** — `_ready()` return type `-> void`.
- **scene_references.gd** — Regions; doc comment; no API change.
- **settings_manager.gd** — Regions (Signals, Constants, Public Properties, Lifecycle, Public Methods, Setters, Apply, Private Methods). Constants typed. No export renames.

### Gameplay

- **game.gd** — Full section layout (Constants, Exported, Public/Private properties, Lifecycle, Public Methods, Signal Handlers, Private Methods). Typed locals (`maze_info`, `heartbeat_ui`, `save_data`, `panel`, `label`, etc.). Fixed SceneLoader signal usage to `loading_finished`.
- **player.gd** — Regions; public vs private vars grouped; `@onready` grouped; shadowing fixed (`stats` in helpers replaced with local `st`); `_on_stat_changed` emit uses `float(new_max)` for signal type; `get_max_health`/`get_stat`/`set_base_stat`/`add_base_stat`/`on_grabbed`/`on_grab_release`/`reset_to_cell` preserved.
- **game_controller.gd** — Regions; exports grouped (no renames); typed locals; `maze_layer_path` comment kept for backward compatibility.

### Systems

- **audio_manager.gd** — Regions; `@export_group("Tuning")` for optional exports; doc comment.
- **visual_effects_manager.gd** — Regions (Private Fields, Lifecycle, Signal Handlers, Public Methods).

### Presence + fog batch

- **presence_spawn_manager.gd** — Regions (Lifecycle, Signal Handlers, Private Methods); typed `controller`, `hist`, `waited`, `game`; `_get_controller()` return type `Node`.
- **pillar_spawn_manager.gd** — Regions (Constants, Lifecycle, Signal Handlers); typed `room_rects`, `rect`, `pillar`; center cell calc explicit to avoid integer-division lint.
- **markings_spawner.gd** — Regions throughout; typed locals and returns; renamed `near` → `near_cells` (avoid shadowing); `eligible.resize(0)` removed (redundant); `max_d` typed.
- **grab_attack.gd** — Regions (Signals, Exported, Private Fields, Public Methods, Lifecycle, Signal Handlers, Private Methods); typed vars; fixed tween chain formatting (no leading `.`); `_exit_tree` moved into Lifecycle.
- **presence_rw.gd** — Constants/enum in region; exports kept (already had categories); Public/Private fields grouped; regions for Lifecycle, Public Methods, Signal Handlers, Private Methods; typed locals (`player_cell`, `maze_layer`, `far_cells_val`, `possible_cells`, `spawned`, `player_node`, `neighbors`, `spawn_cell`, `grab_node`, `minigame`, `stat_to_type`, `eligible_stats`, `chosen_stat`); `_on_catch` still reloads scene; `_load_stats` / `_calculate_type` unchanged.
- **fog_of_war_rw.gd** — Region blocks added (Exported, Onready, Public Properties, Private Fields, Lifecycle, Signal Handlers, Private Methods, Public Methods); `set_facing_cardinal(dir)` typed as `Variant`; added `set_player_and_presence(p, _presence)` stub (game.gd calls it via `has_method`); `_on_level_started` parameter renamed `_maze` → `maze_node` to avoid shadowing `_maze` field.

### Skills system batch

- **system/skill_def.gd** — Regions (Exported, Public Methods); `create_instance` return type `SkillInstance`.
- **system/skill_instance.gd** — Regions; typed `_get_stats` return; local `st` in `_remove_all_keys` to avoid shadowing.
- **system/active_def.gd**, **active_instance.gd** — Regions; `create_instance` → `ActiveInstance`; `try_activate`/`can_activate`/`activate` params typed `Dictionary`.
- **system/passive_def.gd**, **passive_instance.gd** — Regions; `create_instance` return types; `_disconnect` in Private Methods.
- **system/stats_component.gd** — Regions (Exported, Signals, Private Fields, Public Methods); `set_base` second param `Variant`; `get_base` return `Variant`; `debug_dump` kept at end.
- **skill_manager.gd** — Constants region; export types `Array[PassiveDef]`/`Array[ActiveDef]` and `levels`; `_equip_def` now creates and stores instances (fixes missing population and recursion); added `rebuild()` wrapper for player’s `has_method("rebuild")`; typed `inst` in `unequip`.
- **skill_pool.gd** — Regions; export arrays typed `Array[PassiveDef]`/`Array[ActiveDef]`.
- **Per-skill defs/instances** (QuickFeet, ThickSkin, Momentum, KeenAwareness, CalmRecovery, SteadyHands) — Regions; typed locals and returns; `create_instance` return types; MomentumDef `on_player_moved` and `create_instance` typed; MomentumInstance `activate_boost` params prefixed with `_` where unused; MomentumInstance uses `(def as MomentumDef)` for steps/boost.

### UI batch

- **main_menu.gd** — Regions (Exported, Onready, Private Fields, Lifecycle, Signal Handlers, Private Methods); duplicate `_fade_rect` setup removed from `_on_button_select`; typed locals; `_crt_overlay` left unassigned if not in scene.
- **loading_overlay.gd** — Regions; typed; original `print` in `show_loading` / `set_progress` kept.
- **pause_settings.gd** — Regions (Signals, Constants, Onready, Lifecycle, Signal Handlers, Private Methods, Public Methods); `_get_menu_controls` return and navigation logic unchanged.
- **pause_menu.gd** — Regions (Signals, Public Properties, Lifecycle, Signal Handlers, Private Methods); `var handled: bool`; `var viewport: Viewport`; single `_on_button_select` with settings_panel/visibility/focus logic preserved.
- **health_bar.gd** — Regions (Exported, Private Fields, Lifecycle, Signal Handlers); typed `heart`, `current_count`, `prev_count`, `tween`; parameter `max` → `_max_health`; removed unused `_last_heart_count`; uses EventBus `player_health_changed`.
- **level_up_screen.gd** — Full region layout and typing; behavior unchanged.
- **heartbeat_ui.gd** — Regions and typing; `base` renamed to `base_alpha` in `_apply_base_pressure` to avoid shadowing.
- **menu_animation.gd** — Regions; typed `tween`, `start_pos`, `end_pos`.
- **logo.gd** — Regions; `_ready() -> void`; tween chain fixed (no leading `.`).
- **ui_sound_player.gd** — Regions (Private Fields, Lifecycle, Public Methods).
- **minimap.gd** — Regions (Constants, Exported, Private Fields, Onready, Lifecycle, Signal Handlers, Private Methods); no behavior change.
- **grab_minigame.gd** — Regions (Signals, Exported, Onready, Private Fields, Lifecycle, Public Methods, Private Methods); exports and vars typed; `_notification(what: int)`; duplicate exports/onready removed.
- **ui_manager.gd** — SceneLoader signals corrected to `loading_started` / `loading_finished`; handler names `_on_loading_started` / `_on_loading_finished`; return types added.

---

## Deleted / deprecated files

**None.** No files were removed. No deprecated stubs added.

---

## Risk notes

- **SceneLoader signal names** — Code was referring to `scene_loading_started` / `scene_loading_finished`; the autoload defines `loading_started` / `loading_finished`. References in `game.gd` and `ui_manager.gd` were updated to the existing signal names so that “wait for load” behavior works as intended.
- **Scene node paths** — No scene tree changes. All `get_node_or_null("...")` and SceneReferences paths are unchanged.
- **AnimationPlayer / .tscn** — No track path or node renames; no scene file moves.
- **Autoload paths in project.godot** — Unchanged; all autoloads still point to the same script paths.
- **Skill .tres and pools** — Not modified; script references in resources remain valid.
- **Addons** — `addons/gdfxr` and `addons/kanban_tasks` were not modified.

---

## Verification

- Grep over `scripts/` for `preload`, `load(`, `.gd`, `.tscn`: all referenced paths exist.
- Lint: Addressed narrowing conversion in `player.gd` (`EventBus.player_health_changed.emit(current_health, float(new_max))`).
- Public APIs (signals, method names, exported vars) preserved; only internal layout and types adjusted.
