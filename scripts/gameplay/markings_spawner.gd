extends Node2D
class_name MarkingsSpawner

## Spawns decorative floor markings (sprites) in the maze; respects spawn/exit avoidance.

#region Constants
const MARKINGS_TEXTURE: Texture2D = preload("res://sprites/markings.png")
const MARKINGS_SPRITE_SIZE: Vector2i = Vector2i(32, 32)
#endregion

#region Public Properties
var maze: DungeonMazeLayer
var controller: GameController
#endregion

#region Private Fields
var _container: Node2D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
#endregion

#region Lifecycle
func _ready() -> void:
	EventBus.level_started.connect(_on_level_started)
	EventBus.level_transitioning.connect(_on_level_transitioning)
	_ensure_container()
#endregion

#region Public Methods
func set_refs(p_maze: DungeonMazeLayer, p_controller: GameController) -> void:
	maze = p_maze
	controller = p_controller
	_ensure_container()
#endregion

#region Signal Handlers
func _on_level_transitioning() -> void:
	_clear()


func _on_level_started(spawn_cell: Vector2i, p_maze: DungeonMazeLayer) -> void:
	if maze == null:
		maze = p_maze
	_seed_rng_from_maze()
	_spawn_markings(spawn_cell)
#endregion

#region Private Methods
func _ensure_container() -> void:
	if _container != null and is_instance_valid(_container):
		return
	_container = Node2D.new()
	_container.name = "Markings"
	_container.z_index = 0
	add_child(_container)


func _seed_rng_from_maze() -> void:
	if maze == null:
		_rng.randomize()
		return
	if ("rng_seed" in maze) and ("level" in maze) and ("run" in maze):
		_rng.seed = int(maze.rng_seed + int(maze.level) * 1009 + int(maze.run) * 7919 + 424242)
	else:
		_rng.randomize()


func _clear() -> void:
	_ensure_container()
	for n in _container.get_children():
		n.queue_free()


func _is_door_cell(c: Vector2i) -> bool:
	if maze == null:
		return false
	if maze.has_method("is_door_cell"):
		return bool(maze.call("is_door_cell", c))
	if maze.has_method("is_door_closed") and bool(maze.call("is_door_closed", c)):
		return true
	if maze.has_method("is_door_open") and bool(maze.call("is_door_open", c)):
		return true
	return false


func _is_near(a: Vector2i, b: Vector2i, radius_cells: int) -> bool:
	return (abs(a.x - b.x) + abs(a.y - b.y)) <= radius_cells


func _spawn_markings(spawn_cell: Vector2i) -> void:
	if maze == null:
		return

	_clear()

	var used: Rect2i = maze.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return

	var eligible: Array[Vector2i] = []
	for y in range(used.position.y, used.position.y + used.size.y):
		for x in range(used.position.x, used.position.x + used.size.x):
			var c: Vector2i = Vector2i(x, y)
			if not maze.is_floor(c):
				continue
			if _is_door_cell(c):
				continue
			eligible.append(c)

	if eligible.is_empty():
		return

	var floor_count: int = eligible.size()
	var want: int = int(round(float(floor_count) * GameConfig.markings_density_per_floor))
	want = clampi(want, GameConfig.markings_min_per_level, GameConfig.markings_max_per_level)
	if want <= 0:
		return

	var exit_cell: Vector2i = (
		maze.exit_cell if ("exit_cell" in maze) else Vector2i(2147483647, 2147483647)
	)
	var placed_cells: Array[Vector2i] = []

	if want > 0:
		var near_cells: Array[Vector2i] = []
		var min_d: int = GameConfig.markings_avoid_spawn_radius_cells + 1
		var max_d: int = max(min_d, 8)
		for c0 in eligible:
			var d0: int = abs(c0.x - spawn_cell.x) + abs(c0.y - spawn_cell.y)
			if d0 < min_d or d0 > max_d:
				continue
			if (
				exit_cell != Vector2i(2147483647, 2147483647)
				and _is_near(c0, exit_cell, GameConfig.markings_avoid_exit_radius_cells)
			):
				continue
			near_cells.append(c0)

		if not near_cells.is_empty():
			var c_near: Vector2i = near_cells[_rng.randi_range(0, near_cells.size() - 1)]
			_place_one(c_near)
			placed_cells.append(c_near)

	var tries: int = want * 50
	while placed_cells.size() < want and tries > 0:
		tries -= 1
		var c: Vector2i = eligible[_rng.randi_range(0, eligible.size() - 1)]

		if _is_near(c, spawn_cell, GameConfig.markings_avoid_spawn_radius_cells):
			continue
		if (
			exit_cell != Vector2i(2147483647, 2147483647)
			and _is_near(c, exit_cell, GameConfig.markings_avoid_exit_radius_cells)
		):
			continue

		var too_close: bool = false
		for pc in placed_cells:
			if _is_near(c, pc, GameConfig.markings_min_spacing_cells):
				too_close = true
				break
		if too_close:
			continue

		_place_one(c)
		placed_cells.append(c)

	if placed_cells.is_empty():
		print("[Markings] placed 0 / wanted %d" % want)
	else:
		print("[Markings] placed %d / wanted %d at %s" % [placed_cells.size(), want, placed_cells])


func _place_one(cell: Vector2i) -> void:
	_ensure_container()

	var idx: int = _rng.randi_range(0, 2)
	var spr: Sprite2D = Sprite2D.new()
	spr.texture = MARKINGS_TEXTURE
	spr.centered = true
	spr.region_enabled = true
	spr.region_rect = Rect2(
		idx * MARKINGS_SPRITE_SIZE.x, 0, MARKINGS_SPRITE_SIZE.x, MARKINGS_SPRITE_SIZE.y
	)
	spr.z_index = 0
	spr.modulate = Color(1, 1, 1, 1)

	var rot_idx: int = _rng.randi_range(0, 3)
	spr.rotation_degrees = rot_idx * 90

	var world_pos: Vector2
	if controller != null and controller.has_method("cell_to_world_center"):
		world_pos = controller.cell_to_world_center(cell)
	else:
		world_pos = maze.to_global(maze.map_to_local(cell))
	spr.global_position = world_pos

	_container.add_child(spr)
#endregion
