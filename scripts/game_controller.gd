extends Node
class_name GameController

@export var maze_layer_path: NodePath

# Optional convenience refs (you can also assign these at runtime).
@export var player: Node2D
@export var presence: Node2D

@export var trail_add_walk: float = 1.0
@export var trail_add_run: float = 2.0
@export var trail_decay_per_second: float = 0.8
@export var trail_floor: float = 0.0

@export var history_max: int = 250

@onready var maze_layer: MazeLayer = get_node_or_null(maze_layer_path) as MazeLayer

# --- State ---
var trail: Dictionary = {}               # Vector2i -> float
var player_cell: Vector2i = Vector2i.ZERO
var player_history: Array[Vector2i] = [] # oldest -> newest

func _ready() -> void:
	_refresh_refs()

func _process(delta: float) -> void:
	_decay_trail(delta)

func reset_for_new_level() -> void:
	trail.clear()
	player_history.clear()
	player_cell = Vector2i.ZERO

func _refresh_refs() -> void:
	if maze_layer == null and maze_layer_path != NodePath():
		maze_layer = get_node_or_null(maze_layer_path) as MazeLayer

# --- conversions ---
func cell_to_world_center(c: Vector2i) -> Vector2:
	_refresh_refs()
	if maze_layer == null:
		return Vector2.ZERO
	return maze_layer.to_global(maze_layer.map_to_local(c))

func world_to_cell(world_pos: Vector2) -> Vector2i:
	_refresh_refs()
	if maze_layer == null:
		return Vector2i.ZERO
	return maze_layer.local_to_map(maze_layer.to_local(world_pos))

# --- bounds helper: grid size in cells ---
func grid_size_cells() -> Vector2i:
	_refresh_refs()
	if maze_layer == null or maze_layer.tile_set == null:
		return Vector2i.ZERO
	var b: Rect2 = maze_layer.get_world_bounds()
	var ts: Vector2 = maze_layer.tile_set.tile_size
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Vector2i.ZERO
	return Vector2i(int(round(b.size.x / ts.x)), int(round(b.size.y / ts.y)))

# --- walkability ---
func is_walkable(c: Vector2i) -> bool:
	_refresh_refs()
	if maze_layer == null:
		return false
	return maze_layer.is_floor(c)

# --- trail ---
func add_trail_at_world_pos(world_pos: Vector2, amount: float) -> void:
	_refresh_refs()
	if maze_layer == null:
		return
	var c := world_to_cell(world_pos)
	trail[c] = float(trail.get(c, 0.0)) + amount

func get_trail(c: Vector2i) -> float:
	return float(trail.get(c, 0.0))

func _decay_trail(delta: float) -> void:
	if trail.is_empty():
		return
	var decay := trail_decay_per_second * delta
	var to_erase: Array[Vector2i] = []
	for k in trail.keys():
		var v := float(trail[k]) - decay
		if v <= trail_floor + 0.0001:
			to_erase.append(k)
		else:
			trail[k] = v
	for k in to_erase:
		trail.erase(k)

# --- neighbors ---
func get_neighbors4(c: Vector2i) -> Array[Vector2i]:
	return [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]

# --- BFS distance (Manhattan steps through walkable cells) ---
func path_distance(a: Vector2i, b: Vector2i, max_nodes: int = 4000) -> int:
	_refresh_refs()
	if maze_layer == null:
		return 999999
	if a == b:
		return 0
	if not is_walkable(a) or not is_walkable(b):
		return 999999

	var q: Array[Vector2i] = [a]
	var head := 0
	var dist: Dictionary = {a: 0}

	var visited := 0
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

# --- player history (cells visited, oldest -> newest) ---
func record_player_cell(c: Vector2i) -> void:
	player_cell = c  # <-- critical

	if not player_history.is_empty() and player_history[player_history.size() - 1] == c:
		return

	player_history.append(c)
	if player_history.size() > history_max:
		player_history.pop_front()
