extends CharacterBody2D
class_name Player

## Player character: grid movement, vision, health, skills, and interaction.
signal stamina_changed(current: float, max: float)

#region Public Properties
var movement_locked: bool = false
var is_grabbed: bool = false
var cell: Vector2i
var facing: Vector2i = Vector2i.RIGHT
var trail_history: Array[Vector2i] = []
var current_health: float = 0.0
var vision_controller: VisionController = null
#endregion

#region Private Fields
var _move_facing: Vector2i = Vector2i.RIGHT
var _moving: bool = false
var _from: Vector2
var _to: Vector2
var _t: float = 0.0
var _step_duration: float = 0.22
var _eyes_closed: bool = false
var _regen_timer: float = 0.0
var _last_max_health: int = 0
var current_stamina: float = 0.0
var _is_sprinting: bool = false
var _stamina_regen_delay: float = 0.0
#endregion

#region Onready
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var footstep_player: AudioStreamPlayer2D = $FootstepPlayer
@onready var skill_manager: SkillManager = $SkillManager
@onready var stats: Stats = $Stats
@onready var maze: DungeonMazeLayer = get_node_or_null("../TileMap/MazeLayer") as DungeonMazeLayer
@onready var controller: GameController = get_node_or_null("../GameController") as GameController
#endregion


#region Lifecycle
func _ready() -> void:
	_init_stats_from_config()

	if stats and stats.has_signal("stat_changed"):
		stats.stat_changed.connect(_on_stat_changed)

	current_health = _get_max_health()
	_last_max_health = int(_get_max_health())
	EventBus.player_health_changed.emit(current_health, _get_max_health())

	current_stamina = _get_max_stamina()
	emit_signal("stamina_changed", current_stamina, _get_max_stamina())

	if maze == null:
		push_error("[Player] Maze reference not found - player movement will not work")
		return
	if controller == null:
		push_error("[Player] GameController reference not found - player tracking will not work")
		return

	add_to_group("player")

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

	if skill_manager:
		if skill_manager.has_method("rebuild"):
			skill_manager.call("rebuild")
		elif skill_manager.has_method("_rebuild_all"):
			skill_manager.call("_rebuild_all")


func _physics_process(delta: float) -> void:
	_tick_regen(delta)
	_tick_stamina(delta)

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
		_t += delta / _step_duration
		if _t >= 1.0:
			_t = 1.0
		global_position = _from.lerp(_to, _t)
		if _t >= 1.0:
			_moving = false
		return

	if Input.is_action_just_pressed(GameConfig.player_interact_action):
		_try_toggle_door()

	var move_input_held: bool = (
		Input.is_action_pressed("move_up")
		or Input.is_action_pressed("move_down")
		or Input.is_action_pressed("move_left")
		or Input.is_action_pressed("move_right")
	)
	_play_movement_anim(move_input_held, facing)

	var move_dir: Vector2i = Vector2i.ZERO
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
	else:
		_is_sprinting = false


#endregion


#region Public Methods
func setupPlayer() -> void:
	if skill_manager:
		if skill_manager.has_method("rebuild"):
			skill_manager.call("rebuild")
		elif skill_manager.has_method("_rebuild_all"):
			skill_manager.call("_rebuild_all")


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


func get_max_health() -> float:
	return stats.get_stat(&"Max Health")


func get_stat(stat_name: StringName) -> float:
	return float(stats.get_stat(stat_name))


func set_base_stat(stat_name: StringName, value: float) -> void:
	stats.base[stat_name] = value
	stats.stat_changed.emit(stat_name)


func add_base_stat(stat_name: StringName, amount: float) -> void:
	set_base_stat(stat_name, float(stats.base.get(stat_name, 0.0)) + amount)


func on_grabbed() -> void:
	is_grabbed = true
	movement_locked = true
	_play_anim(&"grabbed")


func on_grab_release() -> void:
	is_grabbed = false
	movement_locked = false
	_play_movement_anim(false, facing)


#endregion


#region Signal Handlers
func _on_stat_changed(stat_name: StringName) -> void:
	if stat_name != &"Max Health":
		return
	var new_max: int = int(stats.get_stat(&"Max Health"))
	var delta: int = new_max - _last_max_health
	if delta > 0:
		current_health += delta
	current_health = clampf(current_health, 0.0, float(new_max))
	_last_max_health = new_max
	EventBus.player_health_changed.emit(current_health, float(new_max))


#endregion


#region Private Methods
func _get_step_time() -> float:
	# Walk = slower, Sprint = run speed when stamina > 0
	var use_run: bool = _wants_sprint() and current_stamina > 0.0
	if stats != null and stats.has_method("get_stat"):
		var t: float
		if use_run:
			t = float(stats.call("get_stat", &"Step Time"))
		else:
			t = float(stats.call("get_stat", &"Walk Step Time"))
		return maxf(0.05, t)
	return float(GameConfig.player_step_time if use_run else GameConfig.player_walk_step_time)


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


func _update_look_input() -> void:
	var look_dir: Vector2i = Vector2i.ZERO
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
	var target_cell: Vector2i = cell + dir
	if not maze.is_floor(target_cell):
		return
	var target_pos: Vector2 = _cell_to_global(target_cell)
	var motion: Vector2 = target_pos - global_position
	var collision: KinematicCollision2D = move_and_collide(motion, true)
	if collision != null:
		return

	_move_facing = dir
	facing = dir
	_update_sprite_facing(facing)
	if not _eyes_closed:
		_update_vision_facing()

	var prev_cell: Vector2i = cell
	cell = target_cell
	controller.record_player_cell(cell)
	EventBus.player_moved.emit(prev_cell, cell)
	if skill_manager and skill_manager.has_method("on_player_moved"):
		skill_manager.on_player_moved(prev_cell, cell)

	trail_history.append(cell)
	if trail_history.size() > GameConfig.player_trail_history_max:
		trail_history.pop_front()

	_from = global_position
	_to = target_pos
	_t = 0.0
	_step_duration = _get_step_time()
	_is_sprinting = _wants_sprint() and current_stamina > 0.0
	_moving = true

	if footstep_player:
		footstep_player.stop()
		footstep_player.pitch_scale = randf_range(0.85, 1.15)
		footstep_player.play()

	# Presence trail (sprinting adds more trail)
	var is_running: bool = _is_sprinting
	var amount: float = (
		GameConfig.controller_trail_add_run if is_running else GameConfig.controller_trail_add_walk
	)
	controller.add_trail_at_world_pos(_to, amount)

	if vision_controller and not _eyes_closed:
		vision_controller.reveal_now()


func _try_toggle_door() -> void:
	var target: Vector2i = cell + facing
	if maze and maze.toggle_door_at(target):
		return
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if maze and maze.toggle_door_at(cell + d):
			return


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


func _update_sprite_facing(dir: Vector2i) -> void:
	if anim == null:
		return
	if dir.x != 0:
		anim.flip_h = (dir.x < 0)


func _play_movement_anim(walking: bool, dir: Vector2i) -> void:
	if anim == null or anim.sprite_frames == null:
		return
	_update_sprite_facing(dir)
	var dir_suffix: String = "sideways"
	if dir.y < 0:
		dir_suffix = "up"
	elif dir.y > 0:
		dir_suffix = "down"
	var anim_prefix: String = "run" if walking else "idle"
	var desired: StringName = StringName(anim_prefix + "_" + dir_suffix)
	_play_anim(desired)


func _play_anim(p_name: StringName) -> void:
	if anim == null or anim.sprite_frames == null:
		return
	if not anim.sprite_frames.has_animation(p_name):
		return
	if anim.animation != p_name or not anim.is_playing():
		anim.play(p_name)


func _take_damage(amount: int) -> void:
	current_health = max(current_health - amount, 0.0)
	_reset_regen_delay()
	EventBus.player_health_changed.emit(current_health, _get_max_health())
	if current_health <= 0:
		current_health = 0
		_die()


func _die() -> void:
	SceneLoader.change_scene_with_loading("res://scenes/gameplay/game.tscn")


func _reset_regen_delay() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_regen_timer = maxf(0.0, st.get_stat(&"Regen Delay Seconds"))


func _tick_regen(delta: float) -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	if current_health >= _get_max_health():
		return
	if _regen_timer > 0.0:
		_regen_timer -= delta
		return
	var regen_speed: float = st.get_stat(&"Regen HP Per Second")
	if regen_speed <= 0.0:
		return
	current_health = min(current_health + regen_speed * delta, _get_max_health())
	EventBus.player_health_changed.emit(current_health, _get_max_health())


func _init_stats_from_config() -> void:
	stats.base[&"Agility"] = GameConfig.default_stats["Agility"]
	stats.base[&"Perception"] = GameConfig.default_stats["Perception"]
	stats.base[&"Focus"] = GameConfig.default_stats["Focus"]
	stats.base[&"Resolve"] = GameConfig.default_stats["Resolve"]
	stats.base[&"Composure"] = GameConfig.default_stats["Composure"]
	stats.base[&"Step Time"] = float(GameConfig.player_step_time)
	stats.base[&"Walk Step Time"] = float(GameConfig.player_walk_step_time)
	stats.base[&"Max Health"] = float(GameConfig.player_max_health)
	stats.base[&"Max Stamina"] = float(GameConfig.player_max_stamina)
	stats.base[&"Stamina Drain Per Second"] = float(GameConfig.player_stamina_drain_per_second)
	stats.base[&"Stamina Regen Per Second"] = float(GameConfig.player_stamina_regen_per_second)
	stats.base[&"Stamina Regen Delay Seconds"] = float(
		GameConfig.player_stamina_regen_delay_seconds
	)
	stats.base[&"Stamina Regen Delay After Depleted Seconds"] = float(
		GameConfig.player_stamina_regen_delay_after_depleted_seconds
	)
	stats.base[&"Pillar Charge Time"] = float(GameConfig.pillar_charge_time_seconds)


func _get_stats() -> Stats:
	return get_node_or_null("Stats") as Stats


func _get_max_health() -> float:
	var st: Stats = _get_stats()
	if st == null:
		return 100.0
	return st.get_stat(&"Max Health")


func _get_max_stamina() -> float:
	var s: Stats = _get_stats()
	if s == null:
		return float(GameConfig.player_max_stamina)
	return s.get_stat(&"Max Stamina")


func _wants_sprint() -> bool:
	return Input.is_action_pressed("sprint")


func _tick_stamina(delta: float) -> void:
	var s: Stats = _get_stats()
	if s == null:
		return
	var max_s: float = _get_max_stamina()
	if _moving and _is_sprinting and current_stamina > 0.0:
		var drain: float = s.get_stat(&"Stamina Drain Per Second") * delta
		current_stamina = maxf(0.0, current_stamina - drain)
		_stamina_regen_delay = s.get_stat(&"Stamina Regen Delay Seconds")
		if current_stamina <= 0.0:
			_stamina_regen_delay = s.get_stat(&"Stamina Regen Delay After Depleted Seconds")
		emit_signal("stamina_changed", current_stamina, max_s)
	else:
		if _stamina_regen_delay > 0.0:
			_stamina_regen_delay = maxf(0.0, _stamina_regen_delay - delta)
		elif current_stamina < max_s:
			var regen: float = s.get_stat(&"Stamina Regen Per Second") * delta
			current_stamina = minf(max_s, current_stamina + regen)
			emit_signal("stamina_changed", current_stamina, max_s)
#endregion
