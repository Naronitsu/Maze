extends Node2D
class_name PresenceRW

## Grid-following monster controller.
##
## Responsibilities:
## - Maintain monster position in cell-space (Vector2i).
## - Move on an interval to a neighboring walkable cell.
## - Choose a history-based target ("behind" the player) and chase it.
## - Use the player's trail value as a tie-breaker.
## - Provide a 0..1 pressure value for UI based on distance to the player.
##
## Design goals:
## - Keep all grid/path logic in GameController, and keep this node focused on
##   behavior/decision making.

@export var controller_path: NodePath
@export var move_interval: float = 1.0
@export var wander_if_no_trail: bool = true

@export var near_cells: int = 4
@export var far_cells: int = 25
@export var catch_distance_cells: int = 0

@export var debug_draw: bool = true
@export var debug_radius: float = 6.0
@export var debug_color: Color = Color(1, 0, 0, 0.95)

# How far behind the player history to aim (used by _choose_history_target).
@export var behind_steps: int = 14

# Respawn tuning (history-based spawning)
@export var history_tail_exclusion: int = 18          # newest steps never eligible
@export var min_dist_cells: int = 8                   # must be at least this far from player
@export var max_dist_cells: int = 60                  # ignore super-old/far history
@export var pick_from_best_fraction: float = 0.25     # pick randomly from best N%

const INVALID_CELL := Vector2i(-999999, -999999)
const OFFMAP_POS := Vector2(-1000000.0, -1000000.0)

# Public-ish state (kept for compatibility with your existing code)
var cell: Vector2i = INVALID_CELL

# Internal state
var _active := false
var _prev_cell: Vector2i = INVALID_CELL
var _target_cell: Vector2i = INVALID_CELL
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()

@onready var controller: GameController = _resolve_controller()

func _ready() -> void:
	_rng.randomize()
	# If this node starts without a valid cell, ensure it can't accidentally trigger anything.
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
	# Prefer explicit path, fall back to "../GameController" for backwards compatibility.
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
	_target_cell = INVALID_CELL
	_snap_to_cell()

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func deactivate() -> void:
	_active = false
	cell = INVALID_CELL
	_prev_cell = INVALID_CELL
	_target_cell = INVALID_CELL
	_timer = 0.0

	# Make it "exist nowhere" until you intentionally spawn it.
	global_position = OFFMAP_POS

	# Optional but helpful: guarantees no accidental interactions/visuals.
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
	# If we already have a valid cell, snap immediately.
	_snap_to_cell()
	queue_redraw()

func is_active() -> bool:
	return _active

func respawn_far_from_player(min_dist: int = 18, attempts: int = 800) -> void:
	if controller == null or controller.player == null:
		return

	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	var size: Vector2i = controller.grid_size_cells()

	# If bounds are unknown, fall back to a nearby valid neighbor.
	if size == Vector2i.ZERO:
		for n in controller.get_neighbors4(p_cell):
			if controller.is_walkable(n):
				cell = n
				_prev_cell = cell
				_target_cell = INVALID_CELL
				activate()
				return
		cell = p_cell
		_prev_cell = cell
		_target_cell = INVALID_CELL
		activate()
		return

	for _i in range(attempts):
		var c := Vector2i(_rng.randi_range(0, size.x - 1), _rng.randi_range(0, size.y - 1))
		if not controller.is_walkable(c):
			continue
		var md: int = abs(c.x - p_cell.x) + abs(c.y - p_cell.y)
		if md < min_dist:
			continue
		cell = c
		_prev_cell = cell
		_target_cell = INVALID_CELL
		activate()
		return

	# Last-ditch fallback.
	for n in controller.get_neighbors4(p_cell):
		if controller.is_walkable(n):
			cell = n
			_prev_cell = cell
			_target_cell = INVALID_CELL
			activate()
			return

func get_pressure01() -> float:
	# Critical: no pressure/heartbeat while inactive or unspawned.
	if not _active:
		return 0.0
	if controller == null or controller.player == null:
		return 0.0
	if cell == INVALID_CELL:
		return 0.0

	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	var d: int = controller.path_distance(cell, p_cell)
	# closer -> higher pressure
	var t := inverse_lerp(float(far_cells), float(near_cells), float(d))
	return clampf(t, 0.0, 1.0)

func respawn_from_room_start() -> bool:
	if controller == null or controller.player == null:
		return false

	var history: Array[Vector2i] = controller.player_history
	if history.is_empty():
		return false

	var player_cell: Vector2i = controller.world_to_cell(controller.player.global_position)

	# Cut off future-branch if player backtracked
	var prev_same := -1
	for i in range(history.size() - 2, -1, -1):
		if history[i] == player_cell:
			prev_same = i
			break

	# Keep a small tail exclusion so we don't pop right next to the player.
	var max_tail := maxi(0, history.size() - 1 - 2) # keep at least 2 cells available
	var tail := mini(history_tail_exclusion, max_tail)
	var last_allowed := maxi(0, history.size() - 1 - tail)

	var cutoff := last_allowed
	if prev_same != -1:
		cutoff = mini(cutoff, prev_same)

	# Prefer spawning at a room entrance: corridor (deg<=2) -> room (deg>=3)
	for i in range(cutoff, 0, -1):
		var cur := history[i]
		var prev := history[i - 1]
		if not controller.is_walkable(cur) or not controller.is_walkable(prev):
			continue

		var cur_deg := _walkable_degree(cur)
		var prev_deg := _walkable_degree(prev)
		if prev_deg <= 2 and cur_deg >= 3:
			if cur == player_cell:
				continue
			cell = cur
			_prev_cell = cell
			_target_cell = INVALID_CELL
			activate()
			return true

	# Fallback: oldest available cell on this branch
	var spawn_cell := history[0]
	for i in range(0, cutoff + 1):
		if controller.is_walkable(history[i]):
			spawn_cell = history[i]
			break

	if spawn_cell == player_cell:
		return false

	cell = spawn_cell
	_prev_cell = cell
	_target_cell = INVALID_CELL
	activate()
	return true

func respawn_from_history() -> bool:
	if controller == null:
		print("could not find controller")
		return false

	var history: Array[Vector2i] = controller.player_history
	if history.is_empty():
		print("history empty")
		return false

	# Prefer the real current player cell if we have a player ref
	var player_cell: Vector2i = controller.player_cell
	if controller.player != null:
		player_cell = controller.world_to_cell(controller.player.global_position)

	# Never exclude so much tail that we can't possibly be >= min_dist behind
	var max_tail := maxi(0, history.size() - 1 - min_dist_cells)
	var tail := mini(history_tail_exclusion, max_tail)
	var last_allowed := maxi(0, history.size() - 1 - tail)

	# If player backtracked, ignore the "future branch" after the previous visit
	var prev_same := -1
	for i in range(history.size() - 2, -1, -1):
		if history[i] == player_cell:
			prev_same = i
			break

	var cutoff := last_allowed
	if prev_same != -1:
		cutoff = mini(cutoff, prev_same)

	var pairs: Array[Dictionary] = [] # {"cell": Vector2i, "d": int}
	for i in range(0, cutoff + 1):
		var c: Vector2i = history[i]
		if not controller.is_walkable(c):
			continue

		var d: int = controller.path_distance(c, player_cell)
		if d >= 999999:
			continue
		if d < min_dist_cells or d > max_dist_cells:
			continue
		pairs.append({"cell": c, "d": d})

	if pairs.is_empty():
		print("pairs empty | hist=", history.size(),
			" tail_excl=", history_tail_exclusion,
			" last_allowed=", last_allowed,
			" cutoff=", cutoff,
			" prev_same=", prev_same,
			" player_cell=", player_cell,
			" min=", min_dist_cells,
			" max=", max_dist_cells)
		return false

	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["d"]) < int(b["d"]))

	var top_count := maxi(1, int(ceil(pairs.size() * pick_from_best_fraction)))
	var pick_index := _rng.randi_range(0, top_count - 1)
	cell = pairs[pick_index]["cell"]

	_prev_cell = cell
	_target_cell = INVALID_CELL # force re-target after respawn
	activate()
	return true

# -----------------------------------------------------------------------------
# Internal behavior
# -----------------------------------------------------------------------------

func _step() -> void:
	if controller == null:
		return
	if not _active:
		return

	_ensure_initialized_from_world()
	if cell == INVALID_CELL:
		return

	# Update target occasionally or if invalid
	if _target_cell == INVALID_CELL or not controller.is_walkable(_target_cell):
		_choose_history_target()

	var neighbors: Array[Vector2i] = controller.get_neighbors4(cell)
	if neighbors.is_empty():
		return

	var best_cell := cell
	var best_score := 999999
	var best_trail := -1.0

	for n in neighbors:
		if not controller.is_walkable(n):
			continue
		# Avoid immediate backtrack unless we have no other choice.
		if n == _prev_cell:
			continue

		var score := 999999
		if _target_cell != INVALID_CELL:
			score = controller.path_distance(n, _target_cell)

		# Trail breaks ties (higher is better).
		var t := controller.get_trail(n)
		if score < best_score or (score == best_score and t > best_trail):
			best_score = score
			best_trail = t
			best_cell = n

	# If we blocked ourselves by avoiding backtrack, allow it as fallback.
	if best_cell == cell:
		for n in neighbors:
			if not controller.is_walkable(n):
				continue
			var score := 999999
			if _target_cell != INVALID_CELL:
				score = controller.path_distance(n, _target_cell)
			var t := controller.get_trail(n)
			if score < best_score or (score == best_score and t > best_trail):
				best_score = score
				best_trail = t
				best_cell = n

	_prev_cell = cell
	cell = best_cell
	_snap_to_cell()

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
	var d: int = controller.path_distance(cell, p_cell)
	if d <= catch_distance_cells:
		_on_catch()

func _on_catch() -> void:
	get_tree().reload_current_scene()

func _walkable_degree(c: Vector2i) -> int:
	var d := 0
	for n in controller.get_neighbors4(c):
		if controller.is_walkable(n):
			d += 1
	return d

func _choose_history_target() -> void:
	if controller == null:
		return
	var history: Array[Vector2i] = controller.player_history
	if history.is_empty():
		_target_cell = INVALID_CELL
		return

	# Aim at a cell behind the player (near the end, but not too close)
	var idx: int = max(0, history.size() - 1 - behind_steps)

	# Walk backward a bit to find a walkable one.
	for i in range(idx, -1, -1):
		var c: Vector2i = history[i]
		if controller.is_walkable(c):
			_target_cell = c
			return

	_target_cell = INVALID_CELL
