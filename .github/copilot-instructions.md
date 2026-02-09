# Maze Game - Copilot Instructions

## Project Overview
A Godot 4.5 roguelike maze game where players navigate procedurally-generated dungeons while being hunted by a pursuing "Presence" enemy. Core systems: procedural maze generation, grid-based movement, FOV/fog-of-war rendering, and AI chase behavior.

## Architecture & Data Flow

### Autoload Singletons (Critical)
Four autoloaded singletons provide global state and configuration. Access them directly—no `get_node()` needed:
- **EventBus**: Event-driven communication hub. All inter-component messaging uses signals (`level_started`, `player_moved`, `presence_spawned`, etc.)
- **GameState**: Centralized state machine (`PLAYING`, `TRANSITIONING`, `PAUSED`, `GAME_OVER`). Check `GameState.current` instead of scattered flags
- **GameConfig**: Tuning knobs for all gameplay values (movement speed, spawn distances, vision range). Single source of truth for balancing
- **SaveManager**: Persistence layer for level/run progress

### Scene Hierarchy
- **Game.tscn** (root): Orchestrates level progression via EventBus signals
  - **TileMap/MazeLayer** (`DungeonMazeLayer`): Procedural grid-based maze generator and floor/wall/door tile management
  - **Player** (`CharacterBody2D`): Cell-based movement, FOV tracking, trail writing to GameController
  - **GameController**: Central hub for pathfinding, player history, trail decay
  - **PresenceRW**: AI enemy—chases player, opens doors
  - **PresenceSpawnManager**: Listens to `level_started` signal, spawns presence after head start
  - **Overlay/FogOfWarRW**: Vision raycasting + explored memory shader

### Key Responsibilities

| Component | Purpose | Critical Methods |
|-----------|---------|------------------|
| `tile_map.gd` (DungeonMazeLayer) | Maze generation, door/floor state | `generate()`, `try_open_door_at()`, `is_door_closed()` |
| `game_controller.gd` | Pathfinding hub & player tracking | `path_distance()`, `path_distance_presence()`, `is_passable_for_presence()` |
| `player.gd` | Cell-based movement & vision | `reset_to_cell()`, eyes-closed mechanic |
| `presence_rw.gd` | Enemy AI with door interaction | `respawn_from_history()`, `_best_step_toward_player()` |
| `fog_of_war_rw.gd` | FOV rendering + explored memory | Vision polygon raycasting & shader-based darkness |
| `game.gd` | Level progression orchestrator | Emits `level_started`, waits for intro |
| `presence_spawn_manager.gd` | Presence spawn logic | Subscribes to `level_started`, handles head start timer |

## Event-Driven Architecture Pattern
Use EventBus signals for all inter-component communication—avoid direct method calls:
```gdscript
# Maze — Copilot / Agent Instructions (concise)

Purpose: give an AI coding agent the minimal, project-specific facts to be productive here.

- **Core idea:** Godot 4.x roguelike with procedurally generated mazes, cell-based player movement, FOV/fog-of-war, and a pursuing `Presence` AI. Primary orchestration is event-driven.

- **Autoloads (global singletons):** treat these as globally accessible services (no `get_node()`): [scripts/core/event_bus.gd](scripts/core/event_bus.gd#L1), [scripts/core/game_state.gd](scripts/core/game_state.gd#L1), [scripts/core/game_config.gd](scripts/core/game_config.gd#L1), [scripts/core/save_manager.gd](scripts/core/save_manager.gd#L1). Use `EventBus` signals for cross-component coordination.

- **Primary scenes / scripts to inspect first:** [scenes/gameplay/game.tscn](scenes/gameplay/game.tscn#L1), [scripts/gameplay/game_controller.gd](scripts/gameplay/game_controller.gd#L1), [scripts/gameplay/player.gd](scripts/gameplay/player.gd#L1), [scripts/gameplay/presence_rw.gd](scripts/gameplay/presence_rw.gd#L1), [scripts/gameplay/presence_spawn_manager.gd](scripts/gameplay/presence_spawn_manager.gd#L1), [scripts/gameplay/fog_of_war_rw.gd](scripts/gameplay/fog_of_war_rw.gd#L1).

- **Event pattern:** components emit and connect to `EventBus` signals (e.g., `level_started`, `player_moved`). Prefer wiring via signals over direct function calls between systems.

- **Movement & maze model:** movement is cell-based. `GameController` exposes conversions like `cell_to_world_center()` / `world_to_cell()`. Player history is tracked in `GameController.player_history` and drives `Presence` spawn logic.

- **Presence (AI) notes:** Presence uses BFS pathfinding in `game_controller.gd` helpers (see `path_distance_presence()`), treats closed doors as passable for planning, and actively opens doors when stepping into them. Spawn timing is coordinated by `presence_spawn_manager.gd` and tuned by `GameConfig` values.

- **Fog / vision:** look at [scripts/gameplay/fog_of_war_rw.gd](scripts/gameplay/fog_of_war_rw.gd#L1) plus shader files in `shaders/` for explored vs current vision layering. Player facing is independent from movement.

- **Tile & door conventions:** doors are atlas tiles (not terrain). Door state helpers and masks live with the maze layer / tilemap code — search for `door_closed` / `try_open_door_at` when changing door logic.

- **When editing code:**
  - Keep signal names and payloads stable (breaking them requires updating all listeners).
  - Use `GameConfig` for tuning values instead of sprinkling `@export` values.
  - Respect cell-based APIs on `GameController` rather than manipulating TileMap directly.

- **Useful quick checks / debug knobs:**
  - `presence.debug_draw` (in `presence_rw.gd`) to visualize behavior.
  - Search for `player_history` and `presence_head_start_time` to understand spawn sequencing.

- **How to run / test locally:** open the project root in Godot 4.x (editor or headless CLI). Scenes are under `scenes/`; scripts under `scripts/`.

If any of these summaries should be expanded with code snippets or specific examples (e.g., common signal payloads or a short dev checklist), tell me which area and I will add 1–2 concise examples.
