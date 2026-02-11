## AI-controlled pursuing enemy that chases the player through the maze.
##
## Uses A* pathfinding (via BFS) and can open doors. Spawns using configurable
## strategies (history-based, room-based, or far-spawn).
extends Node2D
class_name PresenceRW

@export_category("Dependencies")
@export var controller: GameController

# Backward compatibility with scene files
@export var controller_path: NodePath

@export_category("Movement")
@export var move_interval: float = 0.45

@export_category("Distance Thresholds")
@export var near_cells: int = 4
@export var far_cells: int = 25
@export var catch_distance_cells: int = 0

@export_category("Debug")
@export var debug_draw: bool = false
@export var debug_radius: float = 6.0
@export var debug_color: Color = Color(1, 0, 0, 0.95)

const INVALID_CELL := Vector2i(-999999, -999999)
const OFFMAP_POS := Vector2(-1000000.0, -1000000.0)

var cell: Vector2i = INVALID_CELL

var _active: bool = false
var _prev_cell: Vector2i = INVALID_CELL
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()

var _last_player_cell: Vector2i = INVALID_CELL

func _ready() -> void:
	# Initialize from NodePath export if direct reference not set (backward compatibility)
	if controller == null and controller_path != NodePath():
		controller = get_node_or_null(controller_path) as GameController
	
	if controller == null:
		push_error("[PresenceRW] GameController reference not found")
		return
	
	_rng.randomize()
	if cell == INVALID_CELL:
		deactivate()
	
	# Listen to events
	EventBus.player_moved.connect(_on_player_moved)
	EventBus.presence_should_spawn.connect(_on_presence_should_spawn)

func _process(delta: float) -> void:
	if not _active or GameState.current != GameState.State.PLAYING:
		return

	_ensure_initialized_from_world()

	# If player stepped into a door tile, open it immediately.
	_open_player_door_if_needed()

	_timer += delta
	if _timer >= GameConfig.presence_move_interval:
		_timer = 0.0
		_step()

	_check_catch()

func _draw() -> void:
	if debug_draw and _active:
		draw_circle(Vector2.ZERO, debug_radius, debug_color)

func _snap_to_cell() -> void:
	if controller == null:
		return
	if cell == INVALID_CELL:
		return
	global_position = controller.cell_to_world_center(cell)
	queue_redraw()

func _ensure_initialized_from_world() -> void:
	if controller == null:
		return
	if cell != INVALID_CELL:
		return
	cell = controller.world_to_cell(global_position)
	_prev_cell = cell
	_snap_to_cell()

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
func deactivate() -> void:
	_active = false
	cell = INVALID_CELL
	_prev_cell = INVALID_CELL
	_timer = 0.0
	_last_player_cell = INVALID_CELL
	global_position = OFFMAP_POS
	visible = false
	set_process(false)
	set_physics_process(false)
	queue_redraw()

func activate() -> void:
	_active = true
	visible = true
	set_process(true)
	set_physics_process(true)
	_timer = 0.0
	_last_player_cell = INVALID_CELL
	_snap_to_cell()
	queue_redraw()

# =========================================================
# Spawn Event Handler
# =========================================================

func _on_presence_should_spawn(player_history: Array) -> void:
	"""Handle presence_should_spawn signal - try spawn chain using strategies"""
	print("[PresenceRW] Received spawn signal (history: %d cells)" % player_history.size())
	
	set_process(false)  # Don't move until spawned
	
	if controller == null:
		push_error("[PresenceRW] No controller available for spawning")
		return
	
	# Try strategies in order: history → room → far
	var strategies: Array[PresenceSpawnStrategy] = [
		PresenceSpawnStrategy.HistoryStrategy.new(controller, controller.maze_layer as DungeonMazeLayer),
		PresenceSpawnStrategy.RoomSpawnStrategy.new(controller, controller.maze_layer as DungeonMazeLayer),
		PresenceSpawnStrategy.FarSpawnStrategy.new(controller, controller.maze_layer as DungeonMazeLayer, GameConfig.presence_min_spawn_dist_cells),
	]
	
	var spawned := false
	for strategy in strategies:
		if strategy.attempt(self):
			spawned = true
			print("[PresenceRW] Spawned via %s" % strategy.get_class())
			break
	
	# Activate if spawned
	if spawned:
		activate()
		EventBus.presence_spawned.emit(cell)
		print("[PresenceRW] Presence activated at %s" % cell)
	else:
		print("[PresenceRW] ERROR: Failed to spawn presence with any strategy")
	
	queue_redraw()

func is_active() -> bool:
	return _active

func get_pressure01() -> float:
	if not _active or controller == null or controller.player == null or cell == INVALID_CELL:
		return 0.0
	var p_cell := controller.world_to_cell(controller.player.global_position)
	var d := _presence_distance(cell, p_cell)
	var t := inverse_lerp(float(GameConfig.presence_far_cells), float(GameConfig.presence_near_cells), float(d))
	return clampf(t, 0.0, 1.0)

func _step() -> void:
	if controller == null or not _active:
		return
	if cell == INVALID_CELL:
		return

	var target_cell := _get_target_cell()
	if target_cell == INVALID_CELL:
		return

	# If we're already on top of the target, nothing to do.
	if target_cell == cell:
		return

	var neighbors := controller.get_neighbors4(cell)
	if neighbors.is_empty():
		return

	var next := _best_step_toward_target(neighbors, target_cell)
	if next == INVALID_CELL:
		return

	# If we are stepping into a closed door tile, open it first.
	_try_open_if_door(next)

	_prev_cell = cell
	cell = next
	_snap_to_cell()
	
	# Emit presence_moved signal
	EventBus.presence_moved.emit(_prev_cell, cell)

func _best_step_toward_target(neighbors: Array[Vector2i], target_cell: Vector2i) -> Vector2i:
	var best := INVALID_CELL
	var best_d := 999999

	# Randomize tie-breaks so the chase doesn't look “grid-perfect”.
	var candidates := neighbors.duplicate()
	candidates.shuffle()

	for n: Vector2i in candidates:
		# Avoid instant backtrack if there are other options.
		if n == _prev_cell and candidates.size() > 1:
			continue
		if not _presence_passable(n):
			continue

		var d := _presence_distance(n, target_cell)
		if d < best_d:
			best_d = d
			best = n

	# If we only found the backtrack, allow it.
	if best == INVALID_CELL:
		for n: Vector2i in candidates:
			if not _presence_passable(n):
				continue
			var d := _presence_distance(n, target_cell)
			if d < best_d:
				best_d = d
				best = n

	return best

func _get_target_cell() -> Vector2i:
	if controller == null or controller.player == null:
		return INVALID_CELL
	return controller.world_to_cell(controller.player.global_position)

# -----------------------------------------------------------------------------
# Door + passability helpers
# -----------------------------------------------------------------------------

func _presence_passable(c: Vector2i) -> bool:
	if controller == null:
		return false
	if controller.has_method("is_passable_for_presence"):
		return bool(controller.call("is_passable_for_presence", c))
	return controller.is_walkable(c)

func _presence_distance(a: Vector2i, b: Vector2i) -> int:
	if controller == null:
		return 999999
	if controller.has_method("path_distance_presence"):
		return int(controller.call("path_distance_presence", a, b))
	return controller.path_distance(a, b)

func _try_open_if_door(c: Vector2i) -> bool:
	if controller == null:
		return false
	if controller.has_method("is_door_closed") and controller.has_method("try_open_door"):
		if bool(controller.call("is_door_closed", c)):
			return bool(controller.call("try_open_door", c))
	return false

func _open_player_door_if_needed() -> void:
	if controller == null or controller.player == null:
		return

	var p_cell := controller.world_to_cell(controller.player.global_position)
	if p_cell == _last_player_cell:
		return
	_last_player_cell = p_cell

	# “Open any doors he enters.”
	_try_open_if_door(p_cell)

# -----------------------------------------------------------------------------
# Catch
# -----------------------------------------------------------------------------

func _check_catch() -> void:
	if not _active:
		return
	if controller == null or controller.player == null:
		return
	if GameConfig.presence_catch_distance_cells < 0:
		return
	if cell == INVALID_CELL:
		return

	var p_cell := controller.world_to_cell(controller.player.global_position)
	var d := _presence_distance(cell, p_cell)
	if d <= GameConfig.presence_catch_distance_cells:
		_on_catch()

func _on_catch() -> void:
	EventBus.presence_caught_player.emit(cell, controller.world_to_cell(controller.player.global_position))
	get_tree().reload_current_scene()

# Event listeners
func _on_player_moved(_from_cell: Vector2i, to_cell: Vector2i) -> void:
	"""Called when player moves, so we can detect door opening."""
	_last_player_cell = to_cell
