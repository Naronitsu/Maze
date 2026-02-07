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
# Game.gd emits when level ready
EventBus.level_started.emit(player.cell, maze)

# PresenceSpawnManager subscribes
EventBus.level_started.connect(_on_level_started)

# Player movement notifies systems
EventBus.player_moved.emit(old_cell, new_cell)
```
This decouples systems: Game.gd doesn't know about PresenceSpawnManager, and vice versa.

## Grid-Based Movement Model
- All movement is **cell-based**, not continuous
- Conversion: `controller.cell_to_world_center(cell)` / `controller.world_to_cell(world_pos)` (never direct TileMap calls)
- Maze is 2D `PackedByteArray`: 0 (wall) / 1 (floor)
- Doors are **non-terrain tiles** (separate layer from terrain autotiling): `door_open_atlas`, `door_closed_atlas`
  - Doors use `_doors_open`/`_doors_closed` arrays + `_door_closed_mask` PackedByteArray for fast lookup

## Presence (Enemy) AI System

**Design Principle**: PresenceRW spawns at level entrance (player history[0]) via PresenceSpawnManager, chases player through maze using doors.

- **Spawn Strategy**: PresenceSpawnManager listens to `level_started` signal, then:
  1. Waits `GameConfig.presence_head_start_time` (default 2.5s)
  2. Waits until player moves `presence_min_history_steps` cells (default 8)
  3. Calls `presence.respawn_from_history()` → `respawn_from_room_start()` → `respawn_far_from_player()` fallback chain
  - Primary spawn: first cell of player history (entrance)
  - Fallback 1: maze spawn cell
  - Fallback 2: random far cell (>12 cells away)
- **Chase Logic**: Uses `path_distance_presence()` which treats **closed doors as passable**
  - This prevents doors from blocking pursuit—presence always finds a path
  - When stepping into a door tile, automatically calls `try_open_door_at()`
  - Also opens doors player steps onto via `_open_player_door_if_needed()`
- **Pathfinding**: BFS in 4 directions (up/down/left/right)
  - `_best_step_toward_player()` selects neighbor with shortest `_presence_distance()` to player
  - Avoids instant backtracking when multiple options exist

## Door System

Doors are **non-passable for the player** until opened, but **passable for presence planning**.

- **Door States**: `is_door_closed(cell)` → bool; `try_open_door_at(cell)` → bool
- **Opening Triggers**:
  1. Player interacts (key press near door) via `toggle_door_at()`
  2. Presence steps into closed door tile (`_try_open_if_door()` in `_step()`)
  3. Presence detects player stepping into door tile (`_open_player_door_if_needed()`)
- **Critical Implementation**:
  - Doors stored in `_doors_open`/`_doors_closed` arrays + `_door_closed_mask` PackedByteArray
  - Doors use **atlas tiles** (`door_open_atlas`, `door_closed_atlas`), not terrain sets
  - Presence can always open closed doors—no trapping allowed
  - Border doors (entrance/exit) cannot be closed

## Player History & Presence Spawning

`GameController.player_history` tracks visited cells (oldest → newest), capped at `history_max`.

- Used by `PresenceSpawnManager` to spawn presence at level entrance (history[0])
- `record_player_cell(cell)` appends cells, avoiding duplicates if same as last cell
- PresenceSpawnManager waits for `presence_min_history_steps` cells before spawning
- Also enables future "trail detection" for more sophisticated AI

## FOV/Fog-of-War Implementation

- **Vision Model**: Raycasting cone from player (configurable angle/distance)
- **Two Layers**:
  1. **Current Vision** (viewport-sized mask): Real-time FOV polygon rendered to mask texture
  2. **Explored Memory** (world-sized mask): Persistent alpha-blended explored areas
- **Shader Integration**: `fog_darkness.gdshader` applies alpha-based darkness/memory
- **Facing System**: Player has independent looking direction (arrow keys) from movement (WASD)
  - `set_facing_cardinal()` updates FOV direction
  - Player script calls `_apply_facing_to_fog()` to sync vision cone
- **Optimization**: Only recomputed when player moves; raycasts against wall bitmask

## Level Progression

- **Level Increment**: `maze.advance_level()` increases size by `size_growth_per_level` each level
- **Run Increment**: `maze.advance_run()` wraps to level 1 after `max_levels_before_reset` (10)
- **Presence Respawn**: Every level transition emits `level_started` signal
  - PresenceSpawnManager waits for `presence_head_start_time` before presence activates
  - Waits for player to move `presence_min_history_steps` cells before spawning
- **Intro Sequence**: New games show door_message intro text; continuing from save skips intro
- **Save System**: SaveManager stores level/run progress; loaded on game start if continuing

## Common Workflows & Patterns

### Add New Enemy Behavior
1. Extend or fork `PresenceRW` (it's a concrete implementation, not abstract)
2. Override `_best_step_toward_player()` for custom pathfinding
3. Override `_step()` to add state machines or decision trees
4. Ensure door opening via `_try_open_if_door()` remains active
5. Update PresenceSpawnManager if spawn logic needs changes

### Modify Maze Generation
- Edit parameters in `tile_map.gd`: `base_width`, `base_height`, `size_growth_per_level`
- Algorithm uses Recursive Backtracking + room carving; see `generate()` method
- Doors spawned at exits of room pairs via `_enforce_two_border_doors_and_floors()`
- Room doors auto-placed by adjacency scan in `_rebuild_room_doors()`

### Adjust Presence Difficulty
- **Speed**: `GameConfig.presence_move_interval` (seconds per step, default 0.45)
- **Spawn Distance**: `GameConfig.presence_min_spawn_dist_cells` (default 12)
- **Head Start**: `GameConfig.presence_head_start_time` (default 2.5s)
- **Catchiness**: `presence.catch_distance_cells` (if >0, triggers catch at distance)

### Debug Presence Movement
- Set `presence.debug_draw = true` to visualize presence position
- `path_distance_presence()` has optional `max_nodes` param to limit BFS iterations
- Check `_last_player_cell` to verify presence door-opening detection
- Use print statements in `_best_step_toward_player()` to trace pathfinding

## Export Variables (Tuning Knobs)

All tuning variables centralized in **GameConfig** singleton (no more scattered @export vars in components):

| Variable | Default | Purpose |
|----------|---------|---------|
| `GameConfig.presence_head_start_time` | 2.5s | Delay before presence spawns |
| `GameConfig.presence_min_spawn_dist_cells` | 12 | Minimum distance for far spawn fallback |
| `GameConfig.presence_move_interval` | 0.45s | Steps per second |
| `GameConfig.player_step_time` | 0.10s | Movement animation duration |
| `GameConfig.maze_base_width/height` | 25 | Starting maze size |
| `GameConfig.fog_vision_range` | 128 world units | FOV distance |
| `GameConfig.player_close_eyes_action` | `&"close_eyes"` | Input action for eyes-closed mechanic |
| `GameConfig.player_interact_action` | `&"interact"` | Input action for door interaction |

## Testing & Validation

- **Spawn Verification**: Check that presence spawns at player history[0], not random location
- **Door Opening**: Verify presence opens doors without getting stuck
- **Level Transitions**: Confirm maze regenerates, player resets, presence re-spawns
- **Trail Decay**: Verify `GameController.trail` decays over time; used for optional trail-following AI
- **Save/Load**: Test continuing from save skips intro, preserves level/run progress

## Files to Know
- **Core Loop**: [game.gd](scripts/game.gd) → [game_controller.gd](scripts/game_controller.gd) → [player.gd](scripts/player.gd) / [presence_rw.gd](scripts/presence_rw.gd)
- **Maze State**: [tile_map.gd](scripts/tile_map.gd) (grid, doors, generation)
- **Vision**: [fog_of_war_rw.gd](scripts/fog_of_war_rw.gd) + [fog_darkness.gdshader](shaders/fog_darkness.gdshader)
- **Scene Layout**: [game.tscn](scenes/game.tscn) (nesting structure)
- **Autoloads**: [event_bus.gd](scripts/core/event_bus.gd), [game_state.gd](scripts/core/game_state.gd), [game_config.gd](scripts/core/game_config.gd), [save_manager.gd](scripts/core/save_manager.gd)

## Godot-Specific Patterns

### Input Actions
All input actions defined in [project.godot](project.godot):
- **Movement**: `move_up/down/left/right` (WASD)
- **Looking**: `look_up/down/left/right` (Arrow keys)
- **Interact**: `interact` (Q key) - opens/closes doors
- **Close Eyes**: `close_eyes` (Space) - disables FOV temporarily
- **Run**: `run` (Shift) - increases trail writing

### TileMapLayer & Terrain
- Floor tiles use **terrain sets** (`terrain_set_id=0`, `floor_terrain_id=0`) for autotiling
- Doors use **atlas tiles** (not terrain) to avoid collision issues
- Wall tiles also use atlas (`wall_atlas = Vector2i(1, 0)`)
- Always use `set_cell(cell, source_id, atlas_coords, alternative_tile)` for non-terrain tiles

### Signal Patterns
```gdscript
# Emitting (no await needed for fire-and-forget)
EventBus.player_moved.emit(old_cell, new_cell)

# Connecting (in _ready())
EventBus.level_started.connect(_on_level_started)

# Awaiting signals for sequencing
await EventBus.level_transitioning
```

### Resource Paths
- Use `res://` protocol for all Godot resource paths
- Scene files: `get_tree().change_scene_to_file("res://scenes/main_menu.tscn")`
- Autoloads accessible globally without `get_node()`: `EventBus`, `GameState`, `GameConfig`, `SaveManager`
