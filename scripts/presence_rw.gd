extends Node2D
class_name PresenceRW
##
## PresenceRW (rewrite)
## - Chases the player directly (shortest-path by BFS distance).
## - Treats CLOSED doors as passable for planning, and opens doors when needed.
## - Also opens any door tile the player steps onto (so it never stays shut “behind” them).
##
## Requires GameController methods used in this project:
## - world_to_cell(), cell_to_world_center(), get_neighbors4()
## - path_distance_presence(a,b)  (treats closed doors as passable)
## - is_passable_for_presence(c)
## - is_door_closed(c), try_open_door(c)
##

@export var controller_path: NodePath
@export var move_interval: float = 0.45

@export var near_cells: int = 4
@export var far_cells: int = 25
@export var catch_distance_cells: int = 0

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

@onready var controller: GameController = _resolve_controller()

func _ready() -> void:
	_rng.randomize()
	if cell == INVALID_CELL:
		deactivate()

func _process(delta: float) -> void:
	if not _active:
		return

	_ensure_initialized_from_world()

	# If player stepped into a door tile, open it immediately.
	_open_player_door_if_needed()

	_timer += delta
	if _timer >= move_interval:
		_timer = 0.0
		_step()

	_check_catch()

func _draw() -> void:
	if debug_draw and _active:
		draw_circle(Vector2.ZERO, debug_radius, debug_color)

func _resolve_controller() -> GameController:
	var gc: GameController = null
	if controller_path != NodePath():
		gc = get_node_or_null(controller_path) as GameController
	if gc == null:
		gc = get_node_or_null("../GameController") as GameController
	return gc

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

func is_active() -> bool:
	return _active

func get_pressure01() -> float:
	if not _active or controller == null or controller.player == null or cell == INVALID_CELL:
		return 0.0
	var p_cell := controller.world_to_cell(controller.player.global_position)
	var d := _presence_distance(cell, p_cell)
	var t := inverse_lerp(float(far_cells), float(near_cells), float(d))
	return clampf(t, 0.0, 1.0)

# Optional convenience spawn
func respawn_far_from_player(min_dist: int = 18, attempts: int = 800) -> void:
	if controller == null or controller.player == null:
		return

	var p_cell := controller.world_to_cell(controller.player.global_position)
	var size := controller.grid_size_cells()

	if size == Vector2i.ZERO:
		for n in controller.get_neighbors4(p_cell):
			if _presence_passable(n):
				cell = n
				_prev_cell = cell
				activate()
				return
		cell = p_cell
		_prev_cell = cell
		activate()
		return

	for _i in range(attempts):
		var c := Vector2i(_rng.randi_range(0, size.x - 1), _rng.randi_range(0, size.y - 1))
		if not _presence_passable(c):
			continue
		var md :int= abs(c.x - p_cell.x) + abs(c.y - p_cell.y)
		if md < min_dist:
			continue
		cell = c
		_prev_cell = cell
		activate()
		return

	for n in controller.get_neighbors4(p_cell):
		if _presence_passable(n):
			cell = n
			_prev_cell = cell
			activate()
			return

# Spawn near the room start (entrance) - called from history
func respawn_from_room_start() -> bool:
	if controller == null:
		return false
	
	# Try to get the maze to find spawn cell
	var maze: Node = null
	if controller.has_meta("maze_ref"):
		maze = controller.get_meta("maze_ref")
	else:
		# Fallback: try to find it in the scene
		var scene = get_tree().current_scene
		if scene != null and scene.has_node("TileMap/MazeLayer"):
			maze = scene.get_node("TileMap/MazeLayer")
	
	if maze == null or not maze.has_method("get_spawn_cell"):
		return false
	
	var spawn_cell: Vector2i = maze.call("get_spawn_cell")
	if not _presence_passable(spawn_cell):
		return false
	
	cell = spawn_cell
	_prev_cell = cell
	activate()
	return true

# Spawn along early player history (behind them at entrance)
func respawn_from_history() -> bool:
	if controller == null:
		return false
	
	var hist: Array = controller.player_history as Array
	if hist.is_empty():
		return false
	
	# Get an early point in history (near the start/entrance)
	# Use the first cell or one of the first few
	var spawn_cell: Vector2i = hist[0] if not hist.is_empty() else Vector2i.ZERO
	
	if not _presence_passable(spawn_cell):
		# Try neighbors if spawn cell isn't passable
		for n in controller.get_neighbors4(spawn_cell):
			if _presence_passable(n):
				spawn_cell = n
				break
	else:
		return false
	
	cell = spawn_cell
	_prev_cell = cell
	activate()
	return true

# Optional convenience spawn
# -----------------------------------------------------------------------------

func _step() -> void:
	if controller == null or not _active:
		return
	if cell == INVALID_CELL:
		return
	if controller.player == null:
		return

	var p_cell := controller.world_to_cell(controller.player.global_position)

	# If we're already on top of the player, nothing to do (catch check handles it).
	if p_cell == cell:
		return

	var neighbors := controller.get_neighbors4(cell)
	if neighbors.is_empty():
		return

	var next := _best_step_toward_player(neighbors, p_cell)
	if next == INVALID_CELL:
		return

	# If we are stepping into a closed door tile, open it first.
	_try_open_if_door(next)

	_prev_cell = cell
	cell = next
	_snap_to_cell()

func _best_step_toward_player(neighbors: Array[Vector2i], player_cell: Vector2i) -> Vector2i:
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

		var d := _presence_distance(n, player_cell)
		if d < best_d:
			best_d = d
			best = n

	# If we only found the backtrack, allow it.
	if best == INVALID_CELL:
		for n: Vector2i in candidates:
			if not _presence_passable(n):
				continue
			var d := _presence_distance(n, player_cell)
			if d < best_d:
				best_d = d
				best = n

	return best

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
	if catch_distance_cells < 0:
		return
	if cell == INVALID_CELL:
		return

	var p_cell := controller.world_to_cell(controller.player.global_position)
	var d := _presence_distance(cell, p_cell)
	if d <= catch_distance_cells:
		_on_catch()

func _on_catch() -> void:
	get_tree().reload_current_scene()
