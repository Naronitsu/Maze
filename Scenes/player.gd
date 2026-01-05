extends CharacterBody2D

@export var step_time: float = 0.10
@export var maze_path: NodePath  # assign TileMap/MazeLayer in inspector

@onready var maze: TileMapLayer = get_node(maze_path)

var _moving := false
var _from: Vector2
var _to: Vector2
var _t := 0.0

var cell: Vector2i

func _ready() -> void:
	# Initialize cell from current global position
	cell = maze.local_to_map(maze.to_local(global_position))
	global_position = _cell_to_global(cell)

func _physics_process(delta: float) -> void:
	if _moving:
		_t += delta / step_time
		if _t >= 1.0:
			_t = 1.0
		global_position = _from.lerp(_to, _t)
		if _t >= 1.0:
			_moving = false
		return

	var dir := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"):
		dir = Vector2i(0, -1)
	elif Input.is_action_just_pressed("move_down"):
		dir = Vector2i(0, 1)
	elif Input.is_action_just_pressed("move_left"):
		dir = Vector2i(-1, 0)
	elif Input.is_action_just_pressed("move_right"):
		dir = Vector2i(1, 0)

	if dir == Vector2i.ZERO:
		return

	_try_step(dir)

func _try_step(dir: Vector2i) -> void:
	var target_cell := cell + dir

	# If you have walls as tiles: block movement when target is a wall
	# Assumes: floor_atlas is used for floors, wall_atlas for walls.
	# If you prefer collision-only, remove this and keep your move_and_collide test.
	var data := maze.get_cell_tile_data(target_cell)
	if data == null:
		return # empty / out of bounds treated as blocked

	# OPTIONAL: if you mark floors via custom data, check that instead.
	# For now, assume any existing tile is walkable; or add your own test.

	var target_pos := _cell_to_global(target_cell)

	# Collision test (keeps your existing safety net)
	var motion := target_pos - global_position
	var collision := move_and_collide(motion, true)
	if collision != null:
		return

	cell = target_cell
	_from = global_position
	_to = target_pos
	_t = 0.0
	_moving = true

func _cell_to_global(c: Vector2i) -> Vector2:
	# map_to_local returns TileMapLayer-local, so convert to global
	return maze.to_global(maze.map_to_local(c))
	
func reset_to_cell(new_cell: Vector2i) -> void:
	cell = new_cell
	_moving = false
	_t = 0.0
	global_position = _cell_to_global(cell)
