# Maze Game - Copilot Instructions

## Project Overview
A Godot 4.5 roguelike maze game where players navigate procedurally-generated dungeons while being hunted by a pursuing "Presence" enemy. Core systems: procedural maze generation, grid-based movement, FOV/fog-of-war rendering, and AI chase behavior.

## Architecture & Data Flow

### Scene Hierarchy
- **Game.tscn** (root): Orchestrates level progression, presence spawning, and door transitions
  - **TileMap/MazeLayer** (`DungeonMazeLayer`): Procedural grid-based maze generator and floor/wall/door tile management
  - **Player** (`CharacterBody2D`): Cell-based movement, FOV tracking, trail writing to GameController
  - **GameController**: Central hub for pathfinding, player history, trail decay
  - **PresenceRW**: AI enemy—chases player, opens doors, spawns at level entrance
  - **Overlay/FogOfWarRW**: Vision raycasting + explored memory shader

### Key Responsibilities

| Component | Purpose | Critical Methods |
|-----------|---------|------------------|
| `tile_map.gd` (DungeonMazeLayer) | Maze generation, door/floor state | `generate()`, `try_open_door_at()`, `is_door_closed()` |
| `game_controller.gd` | Pathfinding hub & player tracking | `path_distance()`, `path_distance_presence()`, `is_passable_for_presence()` |
| `player.gd` | Cell-based movement & vision | `step()`, `reset_to_cell()` |
| `presence_rw.gd` | Enemy AI with door interaction | `respawn_from_history()`, `_best_step_toward_player()` |
| `fog_of_war_rw.gd` | FOV rendering + explored memory | Vision polygon raycasting & shader-based darkness |
| `game.gd` | Level progression & presence spawn orchestration | `_spawn_presence_behind_or_fallback()`, level transitions |

## Grid-Based Movement Model
- All movement is **cell-based**, not continuous
- Conversion between world position ↔ cell: `world_to_cell()` / `cell_to_world_center()` (GameController/TileMapLayer)
- Maze is 2D array of bytes: 0 (wall) / 1 (floor)
- Doors are special non-terrain tiles that block walking but are passable for presence planning

## Presence (Enemy) AI System

**Design Principle**: PresenceRW should spawn at level entrance and chase player through the maze.

- **Spawn Strategy**: `respawn_from_history()` → `respawn_from_room_start()` → `respawn_far_from_player()`
  - Spawns at first cell of player history (entrance) if available
  - Fallback: maze spawn cell
  - Last resort: random far cell (>12 cells away)
- **Chase Logic**: Uses `path_distance_presence()` which treats **closed doors as passable**
  - This prevents doors from blocking pursuit—presence always finds a path
  - When stepping into a door tile, automatically calls `try_open_door_at()`
  - Also opens doors player steps onto via `_open_player_door_if_needed()`
- **Pathfinding**: BFS in 4 directions (up/down/left/right)
  - `_best_step_toward_player()` selects neighbor with shortest distance to player
  - Avoids instant backtracking when multiple options exist

## Door System

Doors are **non-passable for the player** until opened, but **passable for presence planning**.

- **Door States**: `is_door_closed(cell)` → bool; `try_open_door_at(cell)` → bool
- **Opening Triggers**:
  1. Player interacts (key press near door)
  2. Presence steps into closed door tile
  3. Presence detects player stepping into door tile
- **Critical Constraint**: Closing a door must NOT trap the presence
  - Presence can always open closed doors to reach the player
  - No "door memory" that prevents re-opening

## Player History & Presence Spawning

`GameController.player_history` tracks visited cells (oldest → newest), capped at `history_max`.

- Used by `respawn_from_history()` to spawn presence at level entrance
- Also enables future "trail detection" for more sophisticated AI
- Call `record_player_cell(cell)` when player moves; handled by Player script

## FOV/Fog-of-War Implementation

- **Vision Model**: Raycasting cone from player (configurable angle/distance)
- **Two Layers**:
  1. **Current Vision** (viewport-sized mask): Real-time FOV polygon rendered to mask texture
  2. **Explored Memory** (world-sized mask): Persistent alpha-blended explored areas
- **Shader Integration**: `fog_darkness.gdshader` applies alpha-based darkness/memory
- **Optimization**: Only recomputed when player moves; raycasts against wall bitmask

## Level Progression

- **Level Increment**: `maze.advance_level()` increases size by `size_growth_per_level` each level
- **Run Increment**: `maze.advance_run()` wraps to level 1 after `max_levels_before_reset` (10)
- **Presence Respawn**: Every level transition calls `_spawn_presence_behind_or_fallback()`
  - Waits for `presence_head_start_time` before presence activates
  - Waits for player to move `presence_min_history_steps` cells before spawning

## Common Workflows & Patterns

### Add New Enemy Behavior
1. Extend or fork `PresenceRW` (it's a concrete implementation, not abstract)
2. Override `_best_step_toward_player()` for custom pathfinding
3. Override `_step()` to add state machines or decision trees
4. Ensure door opening via `_try_open_if_door()` remains active

### Modify Maze Generation
- Edit parameters in `tile_map.gd`: `base_width`, `base_height`, `size_growth_per_level`
- Algorithm uses Recursive Backtracking + room carving; see `generate()` method
- Doors spawned at exits of room pairs via `_enforce_two_border_doors_and_floors()`

### Adjust Presence Difficulty
- **Speed**: `presence.move_interval` (seconds per step)
- **Spawn Distance**: `presence_min_spawn_dist_cells`
- **Head Start**: `game.presence_head_start_time`
- **Catchiness**: `presence.catch_distance_cells` (if >0, triggers catch at distance)

### Debug Presence Movement
- Set `presence.debug_draw = true` to visualize presence position
- `path_distance_presence()` has optional `max_nodes` param to limit BFS iterations
- Check `_last_player_cell` to verify presence door-opening detection

## Export Variables (Tuning Knobs)

| Variable | Default | Purpose |
|----------|---------|---------|
| `game.presence_head_start_time` | 2.5s | Delay before presence spawns |
| `game.presence_min_spawn_dist_cells` | 12 | Minimum distance for far spawn fallback |
| `presence.move_interval` | 0.45s | Steps per second |
| `player.step_time` | 0.10s | Movement animation duration |
| `maze.base_width/height` | 25 | Starting maze size |
| `fog.visionRange` | 128 world units | FOV distance |

## Testing & Validation

- **Spawn Verification**: Check that presence spawns at player history[0], not random location
- **Door Opening**: Verify presence opens doors without getting stuck
- **Level Transitions**: Confirm maze regenerates, player resets, presence re-spawns
- **Trail Decay**: Verify `GameController.trail` decays over time; used for optional trail-following AI

## Files to Know
- **Core Loop**: `game.gd` → `game_controller.gd` → `player.gd` / `presence_rw.gd`
- **Maze State**: `tile_map.gd` (grid, doors, generation)
- **Vision**: `fog_of_war_rw.gd` + `shaders/fog_darkness.gdshader`
- **Scene Layout**: `scenes/game.tscn` (nesting structure)
