extends Node2D
class_name PresenceRW

## Grid-following monster controller (simplified).
## - Follows the player's *route* (history with backtracking collapsed).
## - Plans through closed doors (treats them as passable) and opens them when needed.
##
## Notes:
## - The GameController already provides `path_distance_presence()` which treats closed doors
##   as passable for planning. This script uses that, and explicitly opens a door when stepping.

@export var controller_path: NodePath
@export var move_interval: float = 0.45

@export var near_cells: int = 4
@export var far_cells: int = 25
@export var catch_distance_cells: int = 0

# How far behind the player route to aim.
@export var behind_steps: int = 14

# Used by respawn_from_history()
@export var history_tail_exclusion: int = 18
@export var min_dist_cells: int = 8
@export var max_dist_cells: int = 60
@export var pick_from_best_fraction: float = 0.25

@export var debug_draw: bool = false
@export var debug_radius: float = 6.0
@export var debug_color: Color = Color(1, 0, 0, 0.95)

const INVALID_CELL := Vector2i(-999999, -999999)
const OFFMAP_POS := Vector2(-1000000.0, -1000000.0)

var cell: Vector2i = INVALID_CELL

var _active := false
var _prev_cell: Vector2i = INVALID_CELL
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()

@onready var controller: GameController = _resolve_controller()

func _ready() -> void:
	_rng.randomize()
	if cell == INVALID_CELL:
		deactivate()

func _process(delta: float) -> void:
	if not _active:
		return
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
	_snap_to_cell()
	queue_redraw()

func is_active() -> bool:
	return _active

func get_pressure01() -> float:
	if not _active or controller == null or controller.player == null or cell == INVALID_CELL:
		return 0.0
	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	var d: int = _presence_distance(cell, p_cell)
	var t := inverse_lerp(float(far_cells), float(near_cells), float(d))
	return clampf(t, 0.0, 1.0)

func respawn_far_from_player(min_dist: int = 18, attempts: int = 800) -> void:
	if controller == null or controller.player == null:
		return

	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	var size: Vector2i = controller.grid_size_cells()

	if size == Vector2i.ZERO:
		# Fallback: a valid neighbor
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
		var md: int = abs(c.x - p_cell.x) + abs(c.y - p_cell.y)
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

func respawn_from_history() -> bool:
	if controller == null:
		return false

	var route := _route_history(controller.player_history)
	if route.is_empty():
		return false

	var player_cell: Vector2i = controller.player_cell
	if controller.player != null:
		player_cell = controller.world_to_cell(controller.player.global_position)

	# Never exclude so much tail that we can't possibly be >= min_dist behind
	var max_tail := maxi(0, route.size() - 1 - min_dist_cells)
	var tail := mini(history_tail_exclusion, max_tail)
	var last_allowed := maxi(0, route.size() - 1 - tail)

	var pairs: Array[Dictionary] = [] # {"cell": Vector2i, "d": int}
	for i in range(0, last_allowed + 1):
		var c: Vector2i = route[i]
		if not _presence_passable(c):
			continue
		var d: int = _presence_distance(c, player_cell)
		if d >= 999999:
			continue
		if d < min_dist_cells or d > max_dist_cells:
			continue
		pairs.append({"cell": c, "d": d})

	if pairs.is_empty():
		return false

	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["d"]) < int(b["d"]))
	var top_count := maxi(1, int(ceil(pairs.size() * pick_from_best_fraction)))
	var pick_index := _rng.randi_range(0, top_count - 1)
	cell = pairs[pick_index]["cell"]
	_prev_cell = cell
	activate()
	return true

# -----------------------------------------------------------------------------
# Core chase behavior
# -----------------------------------------------------------------------------

func _step() -> void:
	if controller == null or not _active:
		return

	_ensure_initialized_from_world()
	if cell == INVALID_CELL:
		return

	var target := _choose_route_target()
	if target == INVALID_CELL:
		return

	var neighbors := controller.get_neighbors4(cell)
	if neighbors.is_empty():
		return

	var next := _best_step_toward(neighbors, target, true)
	if next == INVALID_CELL:
		next = _best_step_toward(neighbors, target, false)
	if next == INVALID_CELL:
		return

	# If we are stepping into a closed door tile, open it first.
	_try_open_if_door(next)

	_prev_cell = cell
	cell = next
	_snap_to_cell()

func _choose_route_target() -> Vector2i:
	if controller == null:
		return INVALID_CELL

	var route := _route_history(controller.player_history)
	if route.is_empty():
		return INVALID_CELL

	# Aim behind the player's current position on the route.
	var idx := maxi(0, route.size() - 1 - behind_steps)
	return route[idx]

func _best_step_toward(neighbors: Array[Vector2i], target: Vector2i, avoid_backtrack: bool) -> Vector2i:
	var best := INVALID_CELL
	var best_d := 999999

	var candidates := neighbors.duplicate()
	candidates.shuffle()

	for n in candidates:
		if avoid_backtrack and n == _prev_cell:
			continue
		if not _presence_passable(n):
			continue

		var d := _presence_distance(n, target)
		if d < best_d:
			best_d = d
			best = n

	return best

# -----------------------------------------------------------------------------
# Backtracking-collapsed "route" helper
# -----------------------------------------------------------------------------

func _route_history(raw: Array[Vector2i]) -> Array[Vector2i]:
	# Collapse loops/backtracking into a single route stack.
	# Example: A->B->C->B->D becomes A->B->D.
	var route: Array[Vector2i] = []
	var index: Dictionary = {}
	for c in raw:
		if index.has(c):
			var keep: int = int(index[c]) + 1
			for k in range(route.size() - 1, keep - 1, -1):
				index.erase(route[k])
				route.pop_back()
		else:
			index[c] = route.size()
			route.append(c)
	return route

# -----------------------------------------------------------------------------
# Door/passability helpers
# -----------------------------------------------------------------------------

func _presence_passable(c: Vector2i) -> bool:
	# Prefer controller's "passable for presence" if available (treats closed doors as passable).
	if controller != null and controller.has_method("is_passable_for_presence"):
		return bool(controller.call("is_passable_for_presence", c))
	return controller != null and controller.is_walkable(c)

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

	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	var d: int = _presence_distance(cell, p_cell)
	if d <= catch_distance_cells:
		_on_catch()

func _on_catch() -> void:
	get_tree().reload_current_scene()
