## Central hub for pathfinding, player tracking, and trail management.
## Provides cell-to-world conversions, walkability checks, BFS pathfinding,
## and maintains player position history for AI spawning.
extends Node
class_name GameController

#region Exported (Inspector)
@export var maze_layer: DungeonMazeLayer
@export var player: Node2D
@export var presence: Node2D
@export var maze_layer_path: NodePath  # Backward compatibility with scene files
#endregion

#region Public Properties
var trail: Dictionary = {}  # Vector2i -> float
var player_cell: Vector2i = Vector2i.ZERO
var player_history: Array[Vector2i] = []
#endregion

#region Lifecycle
func _ready() -> void:
	if maze_layer == null and maze_layer_path != NodePath():
		maze_layer = get_node_or_null(maze_layer_path) as DungeonMazeLayer
	if maze_layer == null:
		push_error("[GameController] maze_layer reference not found")


func _process(delta: float) -> void:
	_decay_trail(delta)
#endregion

#region Public Methods
func reset_for_new_level() -> void:
	trail.clear()
	player_history.clear()
	player_cell = Vector2i.ZERO


func cell_to_world_center(c: Vector2i) -> Vector2:
	if maze_layer == null:
		return Vector2.ZERO
	return maze_layer.to_global(maze_layer.map_to_local(c))


func world_to_cell(world_pos: Vector2) -> Vector2i:
	if maze_layer == null:
		return Vector2i.ZERO
	return maze_layer.local_to_map(maze_layer.to_local(world_pos))


func grid_size_cells() -> Vector2i:
	if maze_layer == null or maze_layer.tile_set == null:
		return Vector2i.ZERO
	var b: Rect2 = maze_layer.get_world_bounds()
	var ts: Vector2 = maze_layer.tile_set.tile_size
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Vector2i.ZERO
	return Vector2i(int(round(b.size.x / ts.x)), int(round(b.size.y / ts.y)))


func is_walkable(c: Vector2i) -> bool:
	if maze_layer == null:
		return false
	return maze_layer.is_floor(c)


func add_trail_at_world_pos(world_pos: Vector2, amount: float) -> void:
	if maze_layer == null:
		return
	var c: Vector2i = world_to_cell(world_pos)
	trail[c] = float(trail.get(c, 0.0)) + amount


func get_trail(c: Vector2i) -> float:
	return float(trail.get(c, 0.0))


func get_neighbors4(c: Vector2i) -> Array[Vector2i]:
	return [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]


func path_distance(a: Vector2i, b: Vector2i, max_nodes: int = 4000) -> int:
	if maze_layer == null:
		return 999999
	if a == b:
		return 0
	if not is_walkable(a) or not is_walkable(b):
		return 999999

	var q: Array[Vector2i] = [a]
	var head: int = 0
	var dist: Dictionary = {a: 0}
	var visited: int = 0
	while head < q.size():
		visited += 1
		if visited > max_nodes:
			break
		var cur: Vector2i = q[head]
		head += 1
		var d: int = int(dist[cur])
		if cur == b:
			return d
		for n: Vector2i in get_neighbors4(cur):
			if not is_walkable(n):
				continue
			if dist.has(n):
				continue
			dist[n] = d + 1
			q.append(n)
	return 999999


func record_player_cell(c: Vector2i) -> void:
	player_cell = c
	if not player_history.is_empty() and player_history[player_history.size() - 1] == c:
		return
	player_history.append(c)
	if player_history.size() > GameConfig.controller_history_max:
		player_history.pop_front()


func try_open_door(cell: Vector2i) -> bool:
	if maze_layer == null:
		return false
	return maze_layer.try_open_door_at(cell)


func is_door_closed(cell: Vector2i) -> bool:
	if maze_layer == null:
		return false
	return maze_layer.is_door_closed(cell)


func is_passable_for_presence(c: Vector2i) -> bool:
	if maze_layer == null:
		return false
	if maze_layer.is_floor(c):
		return true
	return maze_layer.is_door_closed(c)


func path_distance_presence(a: Vector2i, b: Vector2i, max_nodes: int = 4000) -> int:
	if maze_layer == null:
		return 999999
	if a == b:
		return 0
	if not is_passable_for_presence(a) or not is_passable_for_presence(b):
		return 999999

	var q: Array[Vector2i] = [a]
	var head: int = 0
	var dist: Dictionary = {a: 0}
	var visited: int = 0
	while head < q.size():
		visited += 1
		if visited > max_nodes:
			break
		var cur: Vector2i = q[head]
		head += 1
		var cd: int = int(dist[cur])
		if cur == b:
			return cd
		for n: Vector2i in get_neighbors4(cur):
			if not is_passable_for_presence(n):
				continue
			if dist.has(n):
				continue
			dist[n] = cd + 1
			q.append(n)
	return 999999
#endregion

#region Private Methods
func _decay_trail(delta: float) -> void:
	if trail.is_empty():
		return
	var decay: float = GameConfig.controller_trail_decay_per_second * delta
	var to_erase: Array[Vector2i] = []
	for k in trail.keys():
		var v: float = float(trail[k]) - decay
		if v <= GameConfig.controller_trail_floor + 0.0001:
			to_erase.append(k)
		else:
			trail[k] = v
	for k in to_erase:
		trail.erase(k)
#endregion
