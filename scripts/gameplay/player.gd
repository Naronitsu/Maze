extends CharacterBody2D
class_name Player

# --- State flags ---
var movement_locked: bool = false
var is_grabbed: bool = false

# --- Scene refs ---
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var footstep_player: AudioStreamPlayer2D = $FootstepPlayer
@onready var skill_manager: SkillManager = $SkillManager
@onready var stats: Stats = $Stats

@onready var maze: DungeonMazeLayer = get_node_or_null("../TileMap/MazeLayer") as DungeonMazeLayer
@onready var controller: GameController = get_node_or_null("../GameController") as GameController
@onready var health_bar: HBoxContainer = get_node_or_null("../UI/HP/HealthBar") as HBoxContainer

# --- Grid movement ---
var cell: Vector2i
var facing: Vector2i = Vector2i.RIGHT
var _move_facing: Vector2i = Vector2i.RIGHT

var _moving: bool = false
var _from: Vector2
var _to: Vector2
var _t: float = 0.0

# --- Vision / eyes ---
var vision_controller: VisionController = null  # set externally
var _eyes_closed: bool = false

# --- Trail ---
var trail_history: Array[Vector2i] = []

# --- Health ---
var current_health: int = 0
var _last_max_health: int = 0


func _ready() -> void:
	_init_stats_from_config()

	if stats and stats.has_signal("stat_changed"):
		stats.stat_changed.connect(_on_stat_changed)

	current_health = int(stats.get_stat("Max Health"))
	_last_max_health = current_health
	_last_max_health = int(stats.get_stat(&"Max Health"))
	current_health = _last_max_health

	if health_bar:
		health_bar.call("init_hearts")
		health_bar.call("update_hearts")

	if maze == null:
		push_error("[Player] Maze reference not found - player movement will not work")
		return
	if controller == null:
		push_error("[Player] GameController reference not found - player tracking will not work")
		return

	add_to_group("player")

	# Initialize position
	if maze.get_world_bounds().size != Vector2.ZERO:
		cell = maze.local_to_map(maze.to_local(global_position))
	else:
		cell = maze.get_spawn_cell()

	_apply_sprite_scale()
	global_position = _cell_to_global(cell)
	controller.record_player_cell(cell)

	_update_sprite_facing(facing)
	_update_vision_facing()
	_play_movement_anim(false, facing)

	# Build skill instances + apply passives (modifiers) now that Stats exists.
	if skill_manager:
		# If you added a public rebuild() method, use that instead.
		if skill_manager.has_method("rebuild"):
			skill_manager.call("rebuild")
		elif skill_manager.has_method("_rebuild_all"):
			skill_manager.call("_rebuild_all")


func _physics_process(delta: float) -> void:
	if is_grabbed:
		_play_anim(&"grabbed")
		return

	if GameState.current != GameState.State.PLAYING or movement_locked:
		if anim:
			anim.position = Vector2.ZERO
		return

	_update_eyes_state()
	_update_look_input()

	if _moving:
		_play_movement_anim(true, _move_facing)

		_t += delta / _get_step_time()
		if _t >= 1.0:
			_t = 1.0

		global_position = _from.lerp(_to, _t)

		if _t >= 1.0:
			_moving = false
		return

	# Interact
	if Input.is_action_just_pressed(GameConfig.player_interact_action):
		_try_toggle_door()

	# Animation (walking loop) based on held movement input
	var move_input_held := (
		Input.is_action_pressed("move_up")
		or Input.is_action_pressed("move_down")
		or Input.is_action_pressed("move_left")
		or Input.is_action_pressed("move_right")
	)
	_play_movement_anim(move_input_held, facing)

	# Movement input
	var move_dir := Vector2i.ZERO
	if Input.is_action_pressed("move_up"):
		move_dir = Vector2i(0, -1)
	elif Input.is_action_pressed("move_down"):
		move_dir = Vector2i(0, 1)
	elif Input.is_action_pressed("move_left"):
		move_dir = Vector2i(-1, 0)
	elif Input.is_action_pressed("move_right"):
		move_dir = Vector2i(1, 0)

	if move_dir != Vector2i.ZERO:
		_try_step(move_dir)


# ---------------------------
# Skills integration
# ---------------------------


func _get_step_time() -> float:
	# Prefer computed Step Time (base + modifiers)
	if stats != null and stats.has_method("get_stat"):
		var t := float(stats.call("get_stat", &"Step Time"))
		return maxf(0.05, t)  # clamp safety

	# Fallback
	return float(GameConfig.player_step_time)


func setupPlayer() -> void:
	# Keep this for whatever calls it externally
	if skill_manager:
		if skill_manager.has_method("rebuild"):
			skill_manager.call("rebuild")
		elif skill_manager.has_method("_rebuild_all"):
			skill_manager.call("_rebuild_all")


# ---------------------------
# Eyes / vision
# ---------------------------


func _update_eyes_state() -> void:
	var want_closed: bool = Input.is_action_pressed(GameConfig.player_close_eyes_action)
	if want_closed == _eyes_closed:
		return

	_eyes_closed = want_closed
	if _eyes_closed:
		if vision_controller:
			vision_controller.suspend_vision(true)
		EventBus.player_closed_eyes.emit()
	else:
		if vision_controller:
			vision_controller.suspend_vision(false)
			_update_vision_facing()
		EventBus.player_opened_eyes.emit()


func _update_vision_facing() -> void:
	if vision_controller:
		vision_controller.update_facing(facing)


# ---------------------------
# Look / move
# ---------------------------


func _update_look_input() -> void:
	var look_dir := Vector2i.ZERO

	if Input.is_action_just_pressed("look_up"):
		look_dir = Vector2i(0, -1)
	elif Input.is_action_just_pressed("look_down"):
		look_dir = Vector2i(0, 1)
	elif Input.is_action_just_pressed("look_left"):
		look_dir = Vector2i(-1, 0)
	elif Input.is_action_just_pressed("look_right"):
		look_dir = Vector2i(1, 0)

	if look_dir == Vector2i.ZERO:
		return

	facing = look_dir
	_update_sprite_facing(facing)

	if not _eyes_closed:
		_update_vision_facing()
		if vision_controller:
			vision_controller.reveal_now()


func _try_step(dir: Vector2i) -> void:
	if maze == null or controller == null:
		return

	var target_cell := cell + dir

	# Blocked
	if not maze.is_floor(target_cell):
		return

	var target_pos := _cell_to_global(target_cell)

	# Collision safety net
	var motion := target_pos - global_position
	var collision := move_and_collide(motion, true)
	if collision != null:
		return

	# Commit step
	_move_facing = dir
	facing = dir
	_update_sprite_facing(facing)
	if not _eyes_closed:
		_update_vision_facing()

	var prev_cell := cell
	cell = target_cell

	controller.record_player_cell(cell)
	EventBus.player_moved.emit(prev_cell, cell)

	trail_history.append(cell)
	if trail_history.size() > GameConfig.player_trail_history_max:
		trail_history.pop_front()

	_from = global_position
	_to = target_pos
	_t = 0.0
	_moving = true

	# Footsteps
	if footstep_player:
		footstep_player.stop()
		footstep_player.pitch_scale = randf_range(0.85, 1.15)
		footstep_player.play()

	# Presence trail
	var is_running := Input.is_action_pressed("run")
	var amount := (
		GameConfig.controller_trail_add_run if is_running else GameConfig.controller_trail_add_walk
	)
	controller.add_trail_at_world_pos(_to, amount)

	# Snappy FOV update
	if vision_controller and not _eyes_closed:
		vision_controller.reveal_now()


# ---------------------------
# Doors
# ---------------------------


func _try_toggle_door() -> void:
	var target := cell + facing
	if maze and maze.toggle_door_at(target):
		return

	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if maze and maze.toggle_door_at(cell + d):
			return


# ---------------------------
# Position helpers
# ---------------------------


func reset_to_cell(new_cell: Vector2i) -> void:
	cell = new_cell
	_moving = false
	_t = 0.0

	_apply_sprite_scale()
	global_position = _cell_to_global(cell)

	_update_sprite_facing(facing)
	_update_vision_facing()
	if vision_controller:
		vision_controller.reveal_now()

	_play_movement_anim(false, facing)
	if anim:
		anim.position = Vector2.ZERO


func _cell_to_global(c: Vector2i) -> Vector2:
	if controller:
		return controller.cell_to_world_center(c)
	if maze == null:
		return Vector2.ZERO
	return maze.to_global(maze.map_to_local(c))


func _apply_sprite_scale() -> void:
	if anim == null:
		return
	anim.scale = Vector2.ONE * GameConfig.player_sprite_scale
	anim.position = Vector2.ZERO
	if "centered" in anim:
		anim.centered = true


# ---------------------------
# Animation
# ---------------------------


func _update_sprite_facing(dir: Vector2i) -> void:
	if anim == null:
		return
	if dir.x != 0:
		anim.flip_h = (dir.x < 0)


func _play_movement_anim(walking: bool, dir: Vector2i) -> void:
	if anim == null or anim.sprite_frames == null:
		return

	_update_sprite_facing(dir)

	var dir_suffix := "sideways"
	if dir.y < 0:
		dir_suffix = "up"
	elif dir.y > 0:
		dir_suffix = "down"

	var anim_prefix := "run" if walking else "idle"
	var desired: StringName = StringName(anim_prefix + "_" + dir_suffix)
	_play_anim(desired)


func _play_anim(p_name: StringName) -> void:
	if anim == null or anim.sprite_frames == null:
		return
	if not anim.sprite_frames.has_animation(p_name):
		return
	if anim.animation != p_name or not anim.is_playing():
		anim.play(p_name)


# ---------------------------
# Health / damage
# ---------------------------


func _take_damage(amount: int) -> void:
	current_health -= amount
	if health_bar:
		health_bar.call("update_hearts")

	if current_health <= 0:
		current_health = 0
		_die()


func _die() -> void:
	SceneLoader.change_scene_with_loading("res://scenes/gameplay/game.tscn")


# ---------------------------
# Grabbed state hooks
# ---------------------------


func on_grabbed() -> void:
	is_grabbed = true
	movement_locked = true
	_play_anim(&"grabbed")


func on_grab_release() -> void:
	is_grabbed = false
	movement_locked = false
	_play_movement_anim(false, facing)


# ---------------------------
# Your stats API (kept compatible)
# ---------------------------
func get_stat(stat_name: StringName) -> float:
	return float(stats.get_stat(stat_name))


func set_base_stat(stat_name: StringName, value: float) -> void:
	stats.base[stat_name] = value
	stats.stat_changed.emit(stat_name)  # optional, if you rely on signal


func add_base_stat(stat_name: StringName, amount: float) -> void:
	set_base_stat(stat_name, float(stats.base.get(stat_name, 0.0)) + amount)


func _init_stats_from_config() -> void:
	stats.base[&"Agility"] = GameConfig.default_stats["Agility"]
	stats.base[&"Perception"] = GameConfig.default_stats["Perception"]
	stats.base[&"Focus"] = GameConfig.default_stats["Focus"]
	stats.base[&"Resolve"] = GameConfig.default_stats["Resolve"]
	stats.base[&"Composure"] = GameConfig.default_stats["Composure"]

	stats.base[&"Step Time"] = float(GameConfig.player_step_time)
	stats.base[&"Max Health"] = float(GameConfig.player_max_health)


func _on_stat_changed(stat_name: StringName) -> void:
	if stat_name != &"Max Health":
		return

	var new_max := int(stats.get_stat(&"Max Health"))
	var delta := new_max - _last_max_health

	if delta > 0:
		current_health += delta

	current_health = clampi(current_health, 0, new_max)
	_last_max_health = new_max

	if health_bar:
		health_bar.call("init_hearts")
		health_bar.call("update_hearts")
