# Player.gd (tilemap-cell movement + fog-of-war notify)
extends CharacterBody2D

@export var step_time: float = 0.10
@export var maze_path: NodePath            # assign: TileMap/MazeLayer
@export var fog_path: NodePath             # assign: FogOfWar
@export var allow_hold_to_repeat: bool = false
@export var presence_path: NodePath

@onready var maze: MazeLayer = get_node(maze_path) as MazeLayer
@onready var fog: FogOfWar = get_node(fog_path) as FogOfWar
@onready var presence: Node = get_node(presence_path)

var cell: Vector2i

var _moving: bool = false
var _from: Vector2
var _to: Vector2
var _t: float = 0.0

func _ready() -> void:
	# Initialize cell from current global position
	cell = maze.local_to_map(maze.to_local(global_position))
	global_position = _cell_to_global(cell)
	fog.reveal_now()

func _physics_process(delta: float) -> void:
	if _moving:
		_t += delta / step_time
		if _t >= 1.0:
			_t = 1.0
		global_position = _from.lerp(_to, _t)
		if _t >= 1.0:
			_moving = false
			# reveal fog after completing a step
			fog.reveal_now()
		return

	var dir := Vector2i.ZERO

	if allow_hold_to_repeat:
		if Input.is_action_pressed("move_up"):
			dir = Vector2i(0, -1)
		elif Input.is_action_pressed("move_down"):
			dir = Vector2i(0, 1)
		elif Input.is_action_pressed("move_left"):
			dir = Vector2i(-1, 0)
		elif Input.is_action_pressed("move_right"):
			dir = Vector2i(1, 0)
	else:
		if Input.is_action_just_pressed("move_up"):
			dir = Vector2i(0, -1)
		elif Input.is_action_just_pressed("move_down"):
			dir = Vector2i(0, 1)
		elif Input.is_action_just_pressed("move_left"):
			dir = Vector2i(-1, 0)
		elif Input.is_action_just_pressed("move_right"):
			dir = Vector2i(1, 0)

	if dir != Vector2i.ZERO:
		_try_step(dir)

func _try_step(dir: Vector2i) -> void:
	var target_cell: Vector2i = cell + dir

	# Block if not walkable (uses maze's generated grid)
	if not maze.is_floor(target_cell):
		return

	var target_pos: Vector2 = _cell_to_global(target_cell)

	# Collision safety net (optional but good)
	var motion: Vector2 = target_pos - global_position
	var collision := move_and_collide(motion, true)
	if collision != null:
		return

	cell = target_cell
	_from = global_position
	_to = target_pos
	_t = 0.0
	_moving = true
	
	presence.on_player_step(cell)

func reset_to_cell(new_cell: Vector2i) -> void:
	cell = new_cell
	_moving = false
	_t = 0.0
	global_position = _cell_to_global(cell)
	fog.reveal_now()

func _cell_to_global(c: Vector2i) -> Vector2:
	return maze.to_global(maze.map_to_local(c))
