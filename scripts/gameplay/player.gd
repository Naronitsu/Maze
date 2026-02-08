# Player.gd (tilemap-cell movement + grid navigation)
extends CharacterBody2D

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var maze: DungeonMazeLayer = get_node_or_null(NodePath("../TileMap/MazeLayer")) as DungeonMazeLayer
@onready var controller: GameController = get_node_or_null(NodePath("../GameController")) as GameController

var cell: Vector2i
var facing: Vector2i = Vector2i.RIGHT
var _move_facing: Vector2i = Vector2i.RIGHT

var _moving: bool = false
var _from: Vector2
var _to: Vector2
var _t: float = 0.0

var _eyes_closed: bool = false
var _run_grace: float = 0.0

var trail_history: Array[Vector2i] = []

var allow_hold_to_repeat: bool = false

# Will be set by game.gd
var vision_controller: VisionController = null

func _ready() -> void:
	# Core systems are now autoloads
	
	# Initialize position
	if maze != null and maze.get_world_bounds().size != Vector2.ZERO:
		cell = maze.local_to_map(maze.to_local(global_position))
	else:
		cell = maze.get_spawn_cell() if maze != null else Vector2i.ZERO

	global_position = _cell_to_global(cell)

	if controller != null:
		controller.record_player_cell(cell)

	# Initialize vision facing (will be updated once vision_controller is set)
	_update_vision_facing()
	_play_state_anim("idle", facing)

func _physics_process(delta: float) -> void:
	# Only allow input during active gameplay
	if GameState.current != GameState.State.PLAYING:
		return
	
	# Close-eyes state can change even mid-step.
	var want_closed: bool = Input.is_action_pressed(GameConfig.player_close_eyes_action)
	if want_closed != _eyes_closed:
		_eyes_closed = want_closed
		if _eyes_closed:
			if vision_controller != null:
				vision_controller.suspend_vision(true)
			EventBus.player_closed_eyes.emit()
		else:
			if vision_controller != null:
				vision_controller.suspend_vision(false)
				_update_vision_facing()
			EventBus.player_opened_eyes.emit()

	# Update looking direction FIRST (independent of movement)
	_update_look_input()

	# Run grace countdown
	if _run_grace > 0.0:
		_run_grace = maxf(_run_grace - delta, 0.0)

	# If currently moving (interpolating between cells)
	if _moving:
		_play_state_anim("run", _move_facing)

		_t += delta / GameConfig.player_step_time
		if _t >= 1.0:
			_t = 1.0

		global_position = _from.lerp(_to, _t)

		if _t >= 1.0:
			_moving = false
		return

	# Interact: toggle door you're looking at
	if Input.is_action_just_pressed(GameConfig.player_interact_action):
		_try_toggle_door()

	# Not currently interpolating, but still within grace window -> keep run playing
	if _run_grace > 0.0:
		_play_state_anim("run", facing)
	else:
		_play_state_anim("idle", facing)

	# Movement input is separate from look input now
	var move_dir := Vector2i.ZERO
	if allow_hold_to_repeat:
		if Input.is_action_pressed("move_up"):
			move_dir = Vector2i(0, -1)
		elif Input.is_action_pressed("move_down"):
			move_dir = Vector2i(0, 1)
		elif Input.is_action_pressed("move_left"):
			move_dir = Vector2i(-1, 0)
		elif Input.is_action_pressed("move_right"):
			move_dir = Vector2i(1, 0)
	else:
		if Input.is_action_just_pressed("move_up"):
			move_dir = Vector2i(0, -1)
		elif Input.is_action_just_pressed("move_down"):
			move_dir = Vector2i(0, 1)
		elif Input.is_action_just_pressed("move_left"):
			move_dir = Vector2i(-1, 0)
		elif Input.is_action_just_pressed("move_right"):
			move_dir = Vector2i(1, 0)

	if move_dir != Vector2i.ZERO:
		_try_step(move_dir)

func _update_look_input() -> void:
	# Separate look controls: look_up/down/left/right
	# If you map arrows to look_*, you can aim without moving.
	var look_dir := Vector2i.ZERO

	if Input.is_action_just_pressed("look_up"):
		look_dir = Vector2i(0, -1)
	elif Input.is_action_just_pressed("look_down"):
		look_dir = Vector2i(0, 1)
	elif Input.is_action_just_pressed("look_left"):
		look_dir = Vector2i(-1, 0)
	elif Input.is_action_just_pressed("look_right"):
		look_dir = Vector2i(1, 0)

	if look_dir != Vector2i.ZERO:
		facing = look_dir
		# sideways uses flip when facing left
		_update_sprite_facing(facing)

		if not _eyes_closed:
			_update_vision_facing()
			if vision_controller != null:
				vision_controller.reveal_now()

func _try_step(dir: Vector2i) -> void:
	var target_cell: Vector2i = cell + dir

	# If blocked, try opening a door
	if not maze.is_floor(target_cell):
		return

	var target_pos: Vector2 = _cell_to_global(target_cell)

	# Collision safety net (optional but good)
	var motion: Vector2 = target_pos - global_position
	var collision := move_and_collide(motion, true)
	if collision != null:
		return

	# Commit step (rest unchanged)
	_move_facing = dir
	facing = dir
	_update_sprite_facing(facing)
	if not _eyes_closed:
		_update_vision_facing()

	cell = target_cell

	if controller != null:
		controller.record_player_cell(cell)

	# Emit player moved signal for other systems
	var prev_cell = cell - dir
	EventBus.player_moved.emit(prev_cell, cell)

	trail_history.append(cell)
	if trail_history.size() > GameConfig.player_trail_history_max:
		trail_history.pop_front()

	_from = global_position
	_to = target_pos
	_t = 0.0
	_moving = true
	_run_grace = GameConfig.player_run_grace_time

	# Write trail for the Presence to follow
	if controller != null:
		var is_running := Input.is_action_pressed("run")
		var amount := GameConfig.controller_trail_add_run if is_running else GameConfig.controller_trail_add_walk
		controller.add_trail_at_world_pos(_to, amount)

	# Optional: update vision after movement finishes (FOV also updates in _process, but this is snappy)
	if vision_controller != null and not _eyes_closed:
		vision_controller.reveal_now()

func reset_to_cell(new_cell: Vector2i) -> void:
	cell = new_cell
	_moving = false
	_t = 0.0
	_run_grace = 0.0
	global_position = _cell_to_global(cell)

	_update_sprite_facing(facing)
	_update_vision_facing()
	if vision_controller != null:
		vision_controller.reveal_now()

	_play_state_anim("idle", facing)

func _cell_to_global(c: Vector2i) -> Vector2:
	return maze.to_global(maze.map_to_local(c))

func _update_vision_facing() -> void:
	if vision_controller == null:
		return
	# Update FOV direction through centralized vision controller
	vision_controller.update_facing(facing)

func _update_sprite_facing(dir: Vector2i) -> void:
	# Sideways animations are authored as "moving right"
	if anim == null:
		return
	if dir.x != 0:
		anim.flip_h = (dir.x < 0)
	else:
		anim.flip_h = false

func _play_anim(p_name: StringName) -> void:
	if anim == null:
		return
	if anim.sprite_frames == null:
		return
	if not anim.sprite_frames.has_animation(p_name):
		return
	if anim.animation != p_name or not anim.is_playing():
		anim.play(p_name)

func _play_state_anim(state: String, dir: Vector2i) -> void:
	var a := _anim_name_for(state, dir)
	_play_anim(a)

func _anim_name_for(state: String, dir_in: Vector2i) -> StringName:
	var dir := dir_in
	if dir == Vector2i.ZERO:
		dir = facing

	# Sideways: right is default, left is flip
	if dir.x != 0:
		if anim != null:
			anim.flip_h = (dir.x < 0)
		return StringName(state + "_sideways")

	# Vertical: no flip
	if anim != null:
		anim.flip_h = false

	if dir.y < 0:
		return StringName(state + "_up")
	else:
		return StringName(state + "_down")
		
func _try_toggle_door() -> void:
	# Option A: only the cell you're facing (feels intentional)
	var target := cell + facing
	if maze.toggle_door_at(target):
		return

	# Option B (fallback): if not facing a door, try any adjacent door
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if maze.toggle_door_at(cell + d):
			return
