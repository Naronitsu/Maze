## AI-controlled pursuing enemy that chases the player through the maze.
## Uses pathfinding (BFS) and can open doors. Spawns via configurable strategies.
extends Node2D
class_name PresenceRW

#region Constants
enum PresenceType { HUNTER, WATCHER, OBSESSIVE, UNYIELDING, SUFFOCATOR, TUTORIAL }

const INVALID_CELL: Vector2i = Vector2i(-999999, -999999)
const OFFMAP_POS: Vector2 = Vector2(-1000000.0, -1000000.0)
#endregion

#region Exported (Inspector)
@export var presence_type: PresenceType = PresenceType.TUTORIAL

@export_category("Dependencies")
@export var controller: GameController
@export var controller_path: NodePath  # Backward compatibility with scene files
@export var default_stats: Dictionary = {"Agility": 3, "Perception": 3, "Focus": 3, "Resolve": 3, "Composure": 3}

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
#endregion

#region Public Properties
var cell: Vector2i = INVALID_CELL
#endregion

#region Private Fields
var _grab_cd: float = 0.0
var _grab_active: bool = false
var _active: bool = false
var _prev_cell: Vector2i = INVALID_CELL
var _timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_player_cell: Vector2i = INVALID_CELL
#endregion

#region Lifecycle
func _ready() -> void:
	if controller == null and controller_path != NodePath():
		controller = get_node_or_null(controller_path) as GameController

	if controller == null:
		push_error("[PresenceRW] GameController reference not found")
		return

	_rng.randomize()
	if cell == INVALID_CELL:
		deactivate()

	EventBus.player_moved.connect(_on_player_moved)
	EventBus.presence_should_spawn.connect(_on_presence_should_spawn)
	EventBus.level_started.connect(_on_level_started)


func _process(delta: float) -> void:
	if not _active or GameState.current != GameState.State.PLAYING:
		return

	_ensure_initialized_from_world()
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
#endregion

#region Public Methods
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
	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	var d: int = _presence_distance(cell, p_cell)
	var t: float = inverse_lerp(
		float(GameConfig.presence_far_cells), float(GameConfig.presence_near_cells), float(d)
	)
	return clampf(t, 0.0, 1.0)
#endregion

#region Signal Handlers
func _on_level_started(_player_pos: Vector2i, _maze: Node) -> void:
	deactivate()


func _on_player_moved(_from_cell: Vector2i, to_cell: Vector2i) -> void:
	_last_player_cell = to_cell


func _on_presence_should_spawn(player_history: Array) -> void:
	print("[PresenceRW] Received spawn signal (history: %d cells)" % player_history.size())
	set_process(false)

	if controller == null:
		push_error("[PresenceRW] No controller available for spawning")
		return

	var spawned: bool = false
	if controller != null and controller.player != null and controller.maze_layer != null:
		var player_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
		var maze_layer: DungeonMazeLayer = controller.maze_layer
		var far_cells_val: int = 15
		if "presence_min_spawn_dist_cells" in GameConfig:
			far_cells_val = GameConfig.presence_min_spawn_dist_cells
		var possible_cells: Array[Vector2i] = []
		for cell_pos in maze_layer.get_used_cells():
			if (
				controller.path_distance(player_cell, cell_pos) >= far_cells_val
				and controller.is_passable_for_presence(cell_pos)
			):
				possible_cells.append(cell_pos)
		if possible_cells.size() > 0:
			cell = possible_cells[_rng.randi_range(0, possible_cells.size() - 1)]
			_snap_to_cell()
			spawned = true
			print("[PresenceRW] Spawned at random far cell %s" % cell)

	if spawned:
		activate()
		EventBus.presence_spawned.emit(cell)
		print("[PresenceRW] Presence activated at %s" % cell)
	else:
		print("[PresenceRW] ERROR: Failed to spawn presence with any strategy")

	queue_redraw()
#endregion

#region Private Methods
func _snap_to_cell() -> void:
	if controller == null or cell == INVALID_CELL:
		return
	global_position = controller.cell_to_world_center(cell)
	queue_redraw()


func _ensure_initialized_from_world() -> void:
	if controller == null or cell != INVALID_CELL:
		return
	cell = controller.world_to_cell(global_position)
	_prev_cell = cell
	_snap_to_cell()


func _step() -> void:
	if controller == null or not _active or cell == INVALID_CELL:
		return

	var target_cell: Vector2i = _get_target_cell()
	if target_cell == INVALID_CELL or target_cell == cell:
		return

	var neighbors: Array[Vector2i] = controller.get_neighbors4(cell)
	if neighbors.is_empty():
		return

	var next: Vector2i = _best_step_toward_target(neighbors, target_cell)
	if next == INVALID_CELL:
		return

	_try_open_if_door(next)

	_prev_cell = cell
	cell = next
	_snap_to_cell()
	EventBus.presence_moved.emit(_prev_cell, cell)


func _best_step_toward_target(neighbors: Array[Vector2i], target_cell: Vector2i) -> Vector2i:
	var best: Vector2i = INVALID_CELL
	var best_d: int = 999999

	var candidates: Array[Vector2i] = neighbors.duplicate()
	candidates.shuffle()

	for n: Vector2i in candidates:
		if n == _prev_cell and candidates.size() > 1:
			continue
		if not _presence_passable(n):
			continue
		var d: int = _presence_distance(n, target_cell)
		if d < best_d:
			best_d = d
			best = n

	if best == INVALID_CELL:
		for n: Vector2i in candidates:
			if not _presence_passable(n):
				continue
			var d: int = _presence_distance(n, target_cell)
			if d < best_d:
				best_d = d
				best = n

	return best


func _get_target_cell() -> Vector2i:
	if controller == null or controller.player == null:
		return INVALID_CELL
	return controller.world_to_cell(controller.player.global_position)


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
	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	if p_cell == _last_player_cell:
		return
	_last_player_cell = p_cell
	_try_open_if_door(p_cell)


func _check_catch() -> void:
	if not _active or controller == null or controller.player == null:
		return
	if GameConfig.presence_catch_distance_cells < 0 or cell == INVALID_CELL:
		return
	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	var d: int = _presence_distance(cell, p_cell)
	if d <= GameConfig.presence_catch_distance_cells:
		_on_catch()


func _on_catch() -> void:
	EventBus.presence_caught_player.emit(
		cell, controller.world_to_cell(controller.player.global_position)
	)
	get_tree().reload_current_scene()


func _check_grab() -> void:
	if not _active or controller == null or controller.player == null:
		return
	if grab_scene == null or _grab_cd > 0.0 or _grab_active or cell == INVALID_CELL:
		return
	var p_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
	var d: int = _presence_distance(cell, p_cell)
	if d <= grab_range_cells:
		_spawn_grab(p_cell)


func _spawn_grab(target_cell: Vector2i) -> void:
	_grab_cd = grab_cooldown
	_grab_active = true

	var player_node: Node = controller.player
	if player_node:
		player_node.set("movement_locked", true)
		print("[PresenceRW] Player found at global_position=", player_node.global_position, ", cell=", target_cell)

	var neighbors: Array[Vector2i] = controller.get_neighbors4(target_cell)
	var spawn_cell: Vector2i = target_cell
	for n in neighbors:
		if controller.is_walkable(n):
			spawn_cell = n
			break

	var grab_node: Node2D = grab_scene.instantiate() as Node2D
	controller.maze_layer.add_child(grab_node)
	grab_node.global_position = controller.cell_to_world_center(spawn_cell)

	if grab_node.has_method("init_grab"):
		grab_node.call("init_grab", controller.player, controller.cell_to_world_center(spawn_cell))

	var minigame: Node = get_tree().current_scene.get_node_or_null("grabMinigame")
	if minigame:
		if minigame.has_method("start_follow"):
			minigame.call("start_follow", grab_node)
	if grab_node.has_signal("finished"):
		grab_node.connect("finished", Callable(self, "_on_grab_finished"), CONNECT_ONE_SHOT)
	else:
		await get_tree().create_timer(1.2).timeout
		_on_grab_finished()


func _on_grab_finished() -> void:
	_grab_active = false
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
	var stat_to_type: Dictionary = {
		"Agility": PresenceType.HUNTER,
		"Perception": PresenceType.WATCHER,
		"Focus": PresenceType.OBSESSIVE,
		"Resolve": PresenceType.UNYIELDING,
		"Composure": PresenceType.SUFFOCATOR
	}
	var eligible_stats: Array[String] = []
	var max_value: int = 8
	for stat in stat_to_type.keys():
		if default_stats[stat] >= max_value:
			eligible_stats.append(stat)
	if eligible_stats.size() > 0:
		var chosen_stat: String = eligible_stats[_rng.randi_range(0, eligible_stats.size() - 1)]
		presence_type = stat_to_type[chosen_stat]
	else:
		presence_type = PresenceType.TUTORIAL
	print("[PresenceRW] Calculated presence type as %s" % [presence_type])
#endregion
