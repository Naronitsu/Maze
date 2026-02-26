# Maze Roguelike — Copilot Agent Instructions

## Project Overview
A Godot 4.x roguelike maze game: players navigate procedurally-generated dungeons, hunted by a "Presence" AI. Core systems: procedural maze generation, cell-based movement, FOV/fog-of-war, and event-driven AI chase.

## Architecture & Data Flow

- **Autoload Singletons:**
  - [scripts/core/event_bus.gd](scripts/core/event_bus.gd): Global event hub. All cross-system communication uses signals (e.g., `level_started`, `player_moved`).
  - [scripts/core/game_state.gd](scripts/core/game_state.gd): Central state machine (`PLAYING`, `TRANSITIONING`, etc). Use `GameState.current` for state checks.
  - [scripts/core/game_config.gd](scripts/core/game_config.gd): All gameplay tuning values (movement, vision, spawn distances). Use this for balance/configuration.
  - [scripts/core/save_manager.gd](scripts/core/save_manager.gd): Run/level persistence.

- **Scene Hierarchy:**
  - [scenes/gameplay/game.tscn](scenes/gameplay/game.tscn): Root orchestrator, emits `level_started` and manages progression.
    - **DungeonMazeLayer** ([scripts/gameplay/tile_map.gd](scripts/gameplay/tile_map.gd)): Maze/door generation, tile state helpers.
    - **Player** ([scripts/gameplay/player.gd](scripts/gameplay/player.gd)): Cell-based movement, FOV, trail writing.
    - **GameController** ([scripts/gameplay/game_controller.gd](scripts/gameplay/game_controller.gd)): Pathfinding, player history, trail decay.
    - **PresenceRW** ([scripts/gameplay/presence_rw.gd](scripts/gameplay/presence_rw.gd)): AI enemy, BFS pathfinding, door logic.
    - **PresenceSpawnManager** ([scripts/gameplay/presence_spawn_manager.gd](scripts/gameplay/presence_spawn_manager.gd)): Listens for `level_started`, manages spawn delay.
    - **FogOfWarRW** ([scripts/gameplay/fog_of_war_rw.gd](scripts/gameplay/fog_of_war_rw.gd)): Vision raycasting, explored memory shader.

## Project-Specific Patterns & Conventions

- **Event-Driven:** All inter-component communication uses `EventBus` signals. Avoid direct method calls between systems. Example:
  ```gdscript
  EventBus.level_started.emit()
  EventBus.player_moved.connect(_on_player_moved)
  ```

- **Cell-Based Movement:** Use `GameController.cell_to_world_center()` and `world_to_cell()` for all grid/cell conversions. Do not manipulate TileMap directly.

- **AI Pathfinding:** Presence AI uses BFS via `GameController.path_distance_presence()`. Closed doors are considered passable for planning, but Presence opens doors when stepping into them.

- **Door/Tile Conventions:** Doors are atlas tiles (not terrain). Use helpers like `try_open_door_at()` and `is_door_closed()` in `DungeonMazeLayer`.

- **Config & Tuning:** All gameplay values (speeds, vision, spawn times) are set in `GameConfig`. Do not use scattered `@export` values.

- **Debugging:**
  - Set `presence.debug_draw` in `presence_rw.gd` to visualize AI paths.
  - Use `player_history` and `presence_head_start_time` for spawn/debug logic.

## Developer Workflows

- **Run/Test:** Open project root in Godot 4.x editor or run via CLI. Main scenes in `scenes/`, scripts in `scripts/`.
- **Signals:** When adding new signals, update all listeners. Keep payloads stable.
- **Balance:** Adjust values only in `GameConfig`.

## Key Files & Examples

- [scripts/core/event_bus.gd](scripts/core/event_bus.gd): Signal definitions and usage.
- [scripts/gameplay/game_controller.gd](scripts/gameplay/game_controller.gd): Pathfinding, player history, cell/world conversion.
- [scripts/gameplay/presence_rw.gd](scripts/gameplay/presence_rw.gd): AI logic, debug draw.
- [scripts/gameplay/tile_map.gd](scripts/gameplay/tile_map.gd): Maze/door helpers.
- [shaders/fog_darkness_memory.gdshader](shaders/fog_darkness_memory.gdshader): FOV/fog rendering.

---
If you need more detail (e.g., signal payloads, dev checklists, or code snippets), specify the area and request an example.
- **When editing code:**
