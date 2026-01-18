# Player.gd (tilemap-cell movement + fog-of-war notify)
extends CharacterBody2D

@export var step_time: float = 0.10
@export var maze_path: NodePath            # assign: TileMap/MazeLayer
@export var fog_path: NodePath             # assign: FogOfWar
@export var allow_hold_to_repeat: bool = false
@export var presence_path: NodePath

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# Hold this input action to "close eyes".
# While closed: fog resets + stops revealing, and Presence attention drops.
@export var close_eyes_action: StringName = &"close_eyes"

# --- Animation grace: keeps "run" active briefly between tile-steps ---
@export var run_grace_time: float = 0.20
var _run_grace: float = 0.0

@onready var maze: MazeLayer = get_node(maze_path) as MazeLayer
@onready var fog: FogOfWar = get_node(fog_path) as FogOfWar
@onready var presence: Node = get_node(presence_path)

var cell: Vector2i

var _moving: bool = false
var _from: Vector2
var _to: Vector2
var _t: float = 0.0

var _eyes_closed: bool = false

func _ready() -> void:
	if maze == null or maze.get_world_bounds().size == Vector2.ZERO:
		# fallback to current position
		cell = maze.local_to_map(maze.to_local(global_position))
	else:
		cell = maze.get_spawn_cell()
	global_position = _cell_to_global(cell)

	fog.reveal_now()
	_play_anim(&"idle")
	
func _physics_process(delta: float) -> void:
	# Close-eyes state can change even mid-step.
	var want_closed: bool = Input.is_action_pressed(close_eyes_action)
	if want_closed != _eyes_closed:
		_eyes_closed = want_closed
		if _eyes_closed:
			fog.reset_fog()
			fog.set_suspended(true)
			if presence != null and presence.has_method("set_eyes_closed"):
				presence.call("set_eyes_closed", true)
		else:
			fog.set_suspended(false)
			fog.reveal_now()
			if presence != null and presence.has_method("set_eyes_closed"):
				presence.call("set_eyes_closed", false)

	# Run grace countdown
	if _run_grace > 0.0:
		_run_grace = maxf(_run_grace - delta, 0.0)

	# If currently moving (interpolating between cells)
	if _moving:
		_play_anim(&"run")

		_t += delta / step_time
		if _t >= 1.0:
			_t = 1.0

		global_position = _from.lerp(_to, _t)

		if _t >= 1.0:
			_moving = false
			# reveal fog after completing a step
			fog.reveal_now()
		return

	# Not currently interpolating, but still within grace window -> keep run playing
	if _run_grace > 0.0:
		_play_anim(&"run")
	else:
		_play_anim(&"idle")

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

	# Start/refresh the grace timer so "run" doesn't drop to idle between steps
	_run_grace = run_grace_time

	if presence != null and presence.has_method("on_player_step"):
		presence.call("on_player_step", cell)

func reset_to_cell(new_cell: Vector2i) -> void:
	cell = new_cell
	_moving = false
	_t = 0.0
	_run_grace = 0.0
	global_position = _cell_to_global(cell)
	fog.reveal_now()
	_play_anim(&"idle")

func _cell_to_global(c: Vector2i) -> Vector2:
	return maze.to_global(maze.map_to_local(c))

func _play_anim(name: StringName) -> void:
	if anim == null:
		return
	if anim.sprite_frames == null:
		return
	if not anim.sprite_frames.has_animation(name):
		return

	# Don't restart the animation every frame
	if anim.animation != name or not anim.is_playing():
		anim.play(name)
