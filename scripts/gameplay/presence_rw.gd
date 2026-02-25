## AI-controlled pursuing enemy that chases the player through the maze.
##
## Uses A* pathfinding (via BFS) and can open doors. Spawns using configurable
## strategies (history-based, room-based, or far-spawn).
extends Node2D
class_name PresenceRW

enum PresenceType { HUNTER, WATCHER, OBSESSIVE, UNYIELDING, SUFFOCATOR, TUTORIAL }

@export var presence_type: PresenceType = PresenceType.TUTORIAL

@export_category("Dependencies")
@export var controller: GameController

# Backward compatibility with scene files
@export var controller_path: NodePath

@export
var default_stats := {"Agility": 3, "Perception": 3, "Focus": 3, "Resolve": 3, "Composure": 3}

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

@export_category("Grab Attack")
@export var grab_scene: PackedScene
@export var grab_range_cells: int = 2
@export var grab_cooldown: float = 6.0

var _grab_cd: float = 0.0
var _grab_active: bool = false

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
	EventBus.level_started.connect(_on_level_started)


func _on_level_started(_player_pos: Vector2i, _maze: Node) -> void:
	# Despawn presence on new level start
	deactivate()


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

	_grab_cd = maxf(0.0, _grab_cd - delta)
	_check_grab()


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
	# TODO: Replace with actual spawn logic or import PresenceSpawnStrategy implementations.
	# For now, fallback to a simple spawn at a random valid cell far from the player.
	var spawned := false
	if controller != null and controller.player != null and controller.maze_layer != null:
		var player_cell = controller.world_to_cell(controller.player.global_position)
		var maze_layer = controller.maze_layer
		var far_cells = 15
		if "presence_min_spawn_dist_cells" in GameConfig:
			far_cells = GameConfig.presence_min_spawn_dist_cells
		var possible_cells = []
		for cell_pos in maze_layer.get_used_cells():
			if (
				controller.path_distance(player_cell, cell_pos) >= far_cells
				and controller.is_passable_for_presence(cell_pos)
			):
				possible_cells.append(cell_pos)
		if possible_cells.size() > 0:
			cell = possible_cells[_rng.randi_range(0, possible_cells.size() - 1)]
			_snap_to_cell()
			spawned = true
			print("[PresenceRW] Spawned at random far cell %s" % cell)

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
	var t := inverse_lerp(
		float(GameConfig.presence_far_cells), float(GameConfig.presence_near_cells), float(d)
	)
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
	EventBus.presence_caught_player.emit(
		cell, controller.world_to_cell(controller.player.global_position)
	)
	get_tree().reload_current_scene()


# Event listeners
func _on_player_moved(_from_cell: Vector2i, to_cell: Vector2i) -> void:
	"""Called when player moves, so we can detect door opening."""
	_last_player_cell = to_cell


# -----------------------------------------------------------------------------
# Grab Attack
# -----------------------------------------------------------------------------


func _check_grab() -> void:
	if not _active:
		return
	if controller == null or controller.player == null:
		return
	if grab_scene == null:
		return
	if _grab_cd > 0.0:
		return
	if _grab_active:
		return
	if cell == INVALID_CELL:
		return

	var p_cell := controller.world_to_cell(controller.player.global_position)
	var d := _presence_distance(cell, p_cell)  # path distance, not raw grid distance
	if d <= grab_range_cells:
		_spawn_grab(p_cell)


func _spawn_grab(target_cell: Vector2i) -> void:
	_grab_cd = grab_cooldown
	_grab_active = true

	# Disable player movement (requires player.gd to check this flag)
	var player = controller.player
	if player:
		player.set("movement_locked", true)
		print(
			"[PresenceRW] Player found at global_position=",
			player.global_position,
			", cell=",
			target_cell
		)

	# Find available adjacent tile to the player
	var neighbors = controller.get_neighbors4(target_cell)
	var spawn_cell = null
	for n in neighbors:
		if controller.is_walkable(n):
			spawn_cell = n
			break
	if spawn_cell == null:
		# Fallback: use player cell if no adjacent available
		spawn_cell = target_cell

	print(
		"[PresenceRW] Grab will spawn at cell=",
		spawn_cell,
		", world=",
		controller.cell_to_world_center(spawn_cell)
	)

	var grab := grab_scene.instantiate() as Node2D
	controller.maze_layer.add_child(grab)

	var spawn_world := controller.cell_to_world_center(spawn_cell)
	grab.global_position = spawn_world

	# Tell grab who/where to grab
	if grab.has_method("init_grab"):
		grab.call("init_grab", controller.player, spawn_world)

	# Start the minigame UI if present
	var minigame = get_tree().current_scene.get_node_or_null("grabMinigame")
	if minigame:
		print(
			"[PresenceRW] Starting grab minigame UI following grab node at ", grab.global_position
		)
		minigame.start_follow(grab)

	# Listen for grab finish to re-enable player movement
	if grab.has_signal("finished"):
		grab.connect("finished", Callable(self, "_on_grab_finished"), CONNECT_ONE_SHOT)
	else:
		# Fallback: clear after a short time if you haven't added a signal yet.
		await get_tree().create_timer(1.2).timeout
		_on_grab_finished()


func _on_grab_finished() -> void:
	_grab_active = false
	# Re-enable player movement
	if controller and controller.player:
		controller.player.set("movement_locked", false)


func _load_stats(stats: Dictionary) -> void:
	for key in stats.keys():
		if key in default_stats:
			default_stats[key] = stats[key]
			print("[PresenceRW] Loaded stat '%s' with value %s" % [key, stats[key]])
		else:
			print("[PresenceRW] Warning: Unknown stat '%s' in loaded stats" % key)


func _calculate_type() -> void:
	var stat_to_type = {
		"Agility": PresenceType.HUNTER,
		"Perception": PresenceType.WATCHER,
		"Focus": PresenceType.OBSESSIVE,
		"Resolve": PresenceType.UNYIELDING,
		"Composure": PresenceType.SUFFOCATOR
	}
	var eligible_stats = []
	var max_value = 8
	for stat in stat_to_type.keys():
		if default_stats[stat] >= max_value:
			eligible_stats.append(stat)
	if eligible_stats.size() > 0:
		var chosen_stat = eligible_stats[_rng.randi_range(0, eligible_stats.size() - 1)]
		presence_type = stat_to_type[chosen_stat]
	else:
		presence_type = PresenceType.TUTORIAL

	print("[PresenceRW] Calculated presence type as %s" % [presence_type])
