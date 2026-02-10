extends Node2D
class_name MarkingsSpawner

const MARKINGS_TEXTURE: Texture2D = preload("res://sprites/markings.png")
const MARKINGS_SPRITE_SIZE := Vector2i(32, 32)

var maze: DungeonMazeLayer
var controller: GameController

var _container: Node2D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	EventBus.level_started.connect(_on_level_started)
	EventBus.level_transitioning.connect(_on_level_transitioning)

	_ensure_container()

func set_refs(p_maze: DungeonMazeLayer, p_controller: GameController) -> void:
	maze = p_maze
	controller = p_controller
	_ensure_container()

func _on_level_transitioning() -> void:
	_clear()

func _on_level_started(spawn_cell: Vector2i, p_maze: DungeonMazeLayer) -> void:
	if maze == null:
		maze = p_maze
	_seed_rng_from_maze()
	_spawn_markings(spawn_cell)

func _ensure_container() -> void:
	if _container != null and is_instance_valid(_container):
		return
	_container = Node2D.new()
	_container.name = "Markings"
	# TileMap renders at z_index = -1; draw above it so markings are never hidden.
	_container.z_index = 0
	add_child(_container)

func _seed_rng_from_maze() -> void:
	if maze == null:
		_rng.randomize()
		return

	# Mirror the maze's seeded generation so decoration is stable per level/run/seed.
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

	var used := maze.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return

	# Collect eligible floor cells.
	var eligible: Array[Vector2i] = []
	eligible.resize(0)

	for y in range(used.position.y, used.position.y + used.size.y):
		for x in range(used.position.x, used.position.x + used.size.x):
			var c := Vector2i(x, y)
			if not maze.is_floor(c):
				continue
			if _is_door_cell(c):
				continue
			eligible.append(c)

	if eligible.is_empty():
		return

	var floor_count := eligible.size()
	var want := int(round(float(floor_count) * GameConfig.markings_density_per_floor))
	want = clampi(want, GameConfig.markings_min_per_level, GameConfig.markings_max_per_level)
	if want <= 0:
		return

	var exit_cell: Vector2i = (maze.exit_cell if ("exit_cell" in maze) else Vector2i(2147483647, 2147483647))
	var placed_cells: Array[Vector2i] = []

	# Guarantee one marking near spawn (but not right on top of spawn).
	if want > 0:
		var near: Array[Vector2i] = []
		var min_d := GameConfig.markings_avoid_spawn_radius_cells + 1
		var max_d: int = max(min_d, 8)
		for c0 in eligible:
			var d0: int = abs(c0.x - spawn_cell.x) + abs(c0.y - spawn_cell.y)
			if d0 < min_d or d0 > max_d:
				continue
			if exit_cell != Vector2i(2147483647, 2147483647) and _is_near(c0, exit_cell, GameConfig.markings_avoid_exit_radius_cells):
				continue
			near.append(c0)

		if not near.is_empty():
			var c_near := near[_rng.randi_range(0, near.size() - 1)]
			_place_one(c_near)
			placed_cells.append(c_near)

	var tries := want * 50
	while placed_cells.size() < want and tries > 0:
		tries -= 1
		var c: Vector2i = eligible[_rng.randi_range(0, eligible.size() - 1)]

		if _is_near(c, spawn_cell, GameConfig.markings_avoid_spawn_radius_cells):
			continue
		if exit_cell != Vector2i(2147483647, 2147483647) and _is_near(c, exit_cell, GameConfig.markings_avoid_exit_radius_cells):
			continue

		var too_close := false
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
	var spr := Sprite2D.new()
	spr.texture = MARKINGS_TEXTURE
	spr.centered = true
	spr.region_enabled = true
	spr.region_rect = Rect2(idx * MARKINGS_SPRITE_SIZE.x, 0, MARKINGS_SPRITE_SIZE.x, MARKINGS_SPRITE_SIZE.y)
	spr.z_index = 0
	spr.modulate = Color(1, 1, 1, 1)

	var world_pos: Vector2
	if controller != null and controller.has_method("cell_to_world_center"):
		world_pos = controller.cell_to_world_center(cell)
	else:
		world_pos = maze.to_global(maze.map_to_local(cell))
	spr.global_position = world_pos

	_container.add_child(spr)
