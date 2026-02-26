# Script organization

Scripts under `res://scripts/` are grouped by domain. Paths align with `res://scenes/` where applicable.

## Layout

```
scripts/
├── core/           # App bootstrap & global singletons (autoloads)
│   ├── boot.gd
│   ├── event_bus.gd
│   ├── game_config.gd
│   ├── game_state.gd
│   ├── save_manager.gd
│   ├── SceneLoader.gd
│   ├── scene_references.gd
│   └── settings_manager.gd
│
├── gameplay/       # In-game world: game, player, maze, presence, skills
│   ├── game.gd, game_controller.gd, player.gd
│   ├── fog_of_war_rw.gd, presence_rw.gd, presence_spawn_manager.gd
│   ├── pillar.gd, pillar_spawn_manager.gd, markings_spawner.gd
│   ├── level_transition_manager.gd, powerup_*, room_bounce_burst.gd
│   └── skills/
│       ├── skill_manager.gd, skill_pool.gd
│       ├── system/          # skill_def, skill_instance, passive/active, stats_component
│       ├── pools/           # .tres pool resources
│       └── skillScripts/Player/...   # per-skill def/instance + .tres
│
├── level/          # Level / grid data (no scene)
│   └── grid_model.gd
│
├── presence/       # Presence behaviour (grab, spawn strategy)
│   ├── grab/grab_attack.gd
│   └── presence_spawn_strategy.gd
│
├── systems/        # Cross-cutting: audio, VFX, animation, vision
│   ├── audio_manager.gd
│   ├── visual_effects_manager.gd
│   ├── animation_controller.gd
│   └── vision_controller.gd
│
├── ui/             # Menus, HUD, overlays
│   ├── main_menu.gd, pause_menu.gd, pause_settings.gd
│   ├── loading_overlay.gd, level_up_screen.gd
│   ├── health_bar.gd, heartbeat_ui.gd, minimap.gd
│   ├── ui_manager.gd, ui_sound_player.gd, logo.gd, menu_animation.gd
│   └── grab_minigame/grab_minigame.gd
│
├── utils/          # Utility scenes (e.g. transition, level-up flow)
│   └── transition_controller.gd
│
└── world/          # World / tile representation (no scene folder)
    └── tile_map.gd
```

## Rules

- **core/** — Only bootstrap and autoload scripts. No game-specific logic.
- **gameplay/** — Everything that runs during a run: game, player, maze, presence, skills. Scenes live under `scenes/gameplay/` or `scenes/utils/` (SkillManager).
- **presence/** — Presence-related behaviour; scripts used by `scenes/presence/` or by gameplay.
- **systems/** — Shared services (audio, VFX, animation, vision). No scene folder; used from game scene.
- **ui/** — One script per UI scene under `scenes/ui/` (or subfolder like `grab_minigame/`).
- **utils/** — Scripts for utility scenes under `scenes/utils/` (e.g. transition_controller for transition_controller.tscn).
- **level/** — Pure data/level logic (e.g. grid_model). No direct scene.
- **world/** — World representation (e.g. tile_map / DungeonMazeLayer). Used from game scene.

## Moving scripts

When moving a script:

1. Move the `.gd` file and its `.gd.uid` (if present) together.
2. Update every reference:
   - `project.godot` [autoload] if the script is an autoload.
   - Any `preload("res://scripts/...")` or `load("res://scripts/...")` in `.gd` files.
   - `path="res://scripts/..."` in all `.tscn` and `.tres` that reference the script.
3. Code that uses only `class_name` (e.g. `TransitionController`, `VisionController`) does not need changes when the script path changes.

## Recent moves (reorganization)

- **transition_controller.gd** — `core/` → `utils/` (matches `scenes/utils/transition_controller.tscn`). `scenes/utils/transition_controller.tscn` path updated.
- **vision_controller.gd** — `core/` → `systems/` (vision is a system used by game/player).
- **presence_spawn_strategy.gd** — `core/` → `presence/` (presence domain). No path references; only `class_name` usage.
