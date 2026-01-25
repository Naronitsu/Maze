# Player.gd (tilemap-cell movement + fog-of-war notify + trail writing)
extends CharacterBody2D

@export var step_time: float = 0.10
@export var maze_path: NodePath            # assign: TileMap/MazeLayer
@export var fog_path: NodePath             # assign: FogOfWar
@export var allow_hold_to_repeat: bool = false

# NEW: GameController node (trail + path distance utilities)
@export var controller_path: NodePath

# OPTIONAL: Presence node (only needed if you want set_eyes_closed / debug)
@export var presence_path: NodePath

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

@export var close_eyes_action: StringName = &"close_eyes"

# --- Animation grace: keeps "run" active briefly between tile-steps ---
@export var run_grace_time: float = 0.20

@export var trail_history_max: int = 80
var trail_history: Array[Vector2i] = []

var _run_grace: float = 0.0

@onready var maze: DungeonMazeLayer = get_node(maze_path) as DungeonMazeLayer
@onready var fog: FogOfWar = get_node(fog_path) as FogOfWar

# NOTE: GameController is a class_name in my earlier code.
# If you didn't set class_name, change this type to Node and call methods via call().
@onready var controller: GameController = get_node_or_null(controller_path) as GameController
@onready var presence: Node = (get_node(presence_path) if presence_path != NodePath() else null)

var cell: Vector2i

var _moving: bool = false
var _from: Vector2
var _to: Vector2
var _t: float = 0.0

var _eyes_closed: bool = false

func _ready() -> void:
	if maze == null or maze.get_world_bounds().size == Vector2.ZERO:
		cell = maze.local_to_map(maze.to_local(global_position))
	else:
		cell = maze.get_spawn_cell()
	global_position = _cell_to_global(cell)

	if controller != null:
		controller.record_player_cell(cell)

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
			# Optional: tell Presence (prototype can ignore this)
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

	# Commit step
	cell = target_cell

	# Record player history once (controller is authoritative)
	if controller != null:
		controller.record_player_cell(cell)

	trail_history.append(cell)
	if trail_history.size() > trail_history_max:
		trail_history.pop_front()

	# (Optional) local trail_history is kept for any future UI/debug.
	
	_from = global_position
	_to = target_pos
	_t = 0.0
	_moving = true
	_run_grace = run_grace_time

	# NEW: write trail for the Presence to follow
	if controller != null:
		var is_running := Input.is_action_pressed("run") # change if your run action differs
		var amount := controller.trail_add_run if is_running else controller.trail_add_walk
		controller.add_trail_at_world_pos(_to, amount)

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
	if anim.animation != name or not anim.is_playing():
		anim.play(name)
