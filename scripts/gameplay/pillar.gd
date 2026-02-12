extends Node2D
class_name Pillar

const CHARGE_PARTICLE_TEX: Texture2D = preload("res://sprites/map/interactables/pillar/Particles/charge.png")
const CHARGE_LOOP_STREAM: AudioStream = preload("res://sounds/charging.sfxr")
const CHARGE_STAGE_STREAM: AudioStream = preload("res://sounds/charging-stage.sfxr")
const CHARGE_FINISH_STREAM: AudioStream = preload("res://sounds/charge_finish.sfxr")
const SFX_BUS: StringName = &"SFX"

@export var charge_duration_seconds: float = 5.0

@export var idle_anim_name: StringName = &"idle"
@export var charging_anim_name: StringName = &"charging"

var room_rect: Rect2i
var _maze: DungeonMazeLayer
var _started_charging: bool = false
var _player_inside_room: bool = false

var _charge_elapsed: float = 0.0
var _charge_duration: float = 0.0

var _last_stage_idx: int = 0
var _full_charge_burst_fired: bool = false

var _charge_loop_player: AudioStreamPlayer2D
var _charge_stage_player: AudioStreamPlayer2D
var _charge_finish_player: AudioStreamPlayer2D
var _charge_fade_tween: Tween

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("pillars")
	set_process(false)
	if sprite != null:
		_set_idle_visual()
	_setup_audio()
	EventBus.player_moved.connect(_on_player_moved)

func _setup_audio() -> void:
	_charge_loop_player = AudioStreamPlayer2D.new()
	_charge_loop_player.stream = CHARGE_LOOP_STREAM
	_charge_loop_player.bus = SFX_BUS
	_charge_loop_player.max_distance = 500.0
	_charge_loop_player.attenuation = 1.0
	_charge_loop_player.volume_db = -80.0
	_charge_loop_player.finished.connect(_on_charge_loop_finished)
	add_child(_charge_loop_player)

	_charge_stage_player = AudioStreamPlayer2D.new()
	_charge_stage_player.stream = CHARGE_STAGE_STREAM
	_charge_stage_player.bus = SFX_BUS
	_charge_stage_player.max_distance = 500.0
	_charge_stage_player.attenuation = 1.0
	add_child(_charge_stage_player)

	_charge_finish_player = AudioStreamPlayer2D.new()
	_charge_finish_player.stream = CHARGE_FINISH_STREAM
	_charge_finish_player.bus = SFX_BUS
	_charge_finish_player.max_distance = 500.0
	_charge_finish_player.attenuation = 1.0
	add_child(_charge_finish_player)

func _on_charge_loop_finished() -> void:
	# Keep looping while actively charging.
	if not _started_charging:
		return
	if _is_fully_charged():
		return
	if _charge_loop_player == null:
		return
	# If we're mid fade-out, don't restart.
	if _charge_loop_player.volume_db <= -60.0:
		return
	_charge_loop_player.play()

func _play_charge_loop() -> void:
	if _charge_loop_player == null or _charge_loop_player.stream == null:
		return
	if _charge_fade_tween != null and is_instance_valid(_charge_fade_tween):
		_charge_fade_tween.kill()

	# Play at normal pitch and loop via `_on_charge_loop_finished`.
	_charge_loop_player.pitch_scale = 1.0

	_charge_loop_player.volume_db = -14.0
	# Ensure we always restart from the beginning when charging starts.
	_charge_loop_player.stop()
	_charge_loop_player.play()
	# Quick fade in.
	_charge_fade_tween = create_tween()
	_charge_fade_tween.tween_property(_charge_loop_player, "volume_db", -6.0, 0.20)

func _stop_charge_loop_fade_out() -> void:
	if _charge_loop_player == null:
		return
	if _charge_fade_tween != null and is_instance_valid(_charge_fade_tween):
		_charge_fade_tween.kill()
	if not _charge_loop_player.playing:
		_charge_loop_player.volume_db = -80.0
		return
	_charge_fade_tween = create_tween()
	_charge_fade_tween.tween_property(_charge_loop_player, "volume_db", -80.0, 0.35)
	_charge_fade_tween.tween_callback(func():
		if _charge_loop_player != null:
			_charge_loop_player.stop()
	)

func _play_charge_stage_sfx() -> void:
	if _charge_stage_player == null or _charge_stage_player.stream == null:
		return
	_charge_stage_player.play()

func _play_charge_finish_sfx() -> void:
	if _charge_finish_player == null or _charge_finish_player.stream == null:
		return
	_charge_finish_player.play()

func _set_idle_visual() -> void:
	if sprite == null:
		return
	if sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(idle_anim_name):
		return
	sprite.animation = idle_anim_name
	sprite.frame = 0
	sprite.stop()

func setup(p_room_rect: Rect2i, initial_player_cell: Vector2i, p_maze: DungeonMazeLayer = null) -> void:
	room_rect = p_room_rect
	_maze = p_maze
	_player_inside_room = room_rect.has_point(initial_player_cell)
	if _player_inside_room:
		_start_charging()

func _on_player_moved(_from_cell: Vector2i, to_cell: Vector2i) -> void:
	var inside := room_rect.has_point(to_cell)
	if _started_charging:
		# If the player leaves before completion, reset back to idle.
		if _player_inside_room and not inside and not _is_fully_charged():
			_reset_charge()
		_player_inside_room = inside
		return

	_player_inside_room = inside
	if inside:
		_start_charging()

func _is_fully_charged() -> bool:
	if not _started_charging:
		return false
	var duration := maxf(_charge_duration, 0.001)
	return _charge_elapsed >= duration

func _reset_charge() -> void:
	_started_charging = false
	_charge_elapsed = 0.0
	_last_stage_idx = 0
	_full_charge_burst_fired = false
	_stop_charge_loop_fade_out()
	set_process(false)
	_set_idle_visual()

func _start_charging() -> void:
	_started_charging = true
	_charge_elapsed = 0.0
	_full_charge_burst_fired = false
	_charge_duration = float(GameConfig.pillar_charge_time_seconds)
	if _charge_duration <= 0.0:
		_charge_duration = charge_duration_seconds
	_play_charge_loop()
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(charging_anim_name):
		sprite.animation = charging_anim_name
		sprite.stop()
		sprite.frame = 0
		_last_stage_idx = 0
	set_process(true)

func _process(delta: float) -> void:
	if not _started_charging:
		return
	if sprite == null or sprite.sprite_frames == null:
		set_process(false)
		return
	if not sprite.sprite_frames.has_animation(charging_anim_name):
		set_process(false)
		return

	_charge_elapsed += delta
	var duration := maxf(_charge_duration, 0.001)
	var t := clampf(_charge_elapsed / duration, 0.0, 1.0)

	var frame_count := sprite.sprite_frames.get_frame_count(charging_anim_name)
	if frame_count <= 0:
		set_process(false)
		return

	# Each frame represents an equal 20% chunk when frame_count == 5.
	var idx := int(floor(t * float(frame_count)))
	idx = clampi(idx, 0, frame_count - 1)

	if idx != _last_stage_idx:
		_last_stage_idx = idx
		# Smaller bursts on phase thresholds (20/40/60/80%).
		if idx >= 1:
			_play_charge_stage_sfx()
			_burst_room_particles_small(idx)

	sprite.animation = charging_anim_name
	sprite.stop()
	sprite.frame = idx

	if _charge_elapsed >= duration:
		if not _full_charge_burst_fired:
			_full_charge_burst_fired = true
			_play_charge_finish_sfx()
			_burst_room_particles_full()
			_stop_charge_loop_fade_out()
		set_process(false)

func _burst_room_particles_small(stage_idx: int) -> void:
	if _maze == null:
		# Best-effort fallback: try to find the maze layer in the running scene.
		_maze = get_tree().get_first_node_in_group("maze") as DungeonMazeLayer
		if _maze == null:
			_maze = get_node_or_null("../TileMap/MazeLayer") as DungeonMazeLayer
	if _maze == null:
		return

	var bounds := _room_bounds_world(_maze, room_rect)
	if bounds.size == Vector2.ZERO:
		return

	var burst := RoomBounceBurst.new()
	burst.set_as_top_level(true)
	burst.global_position = Vector2.ZERO
	burst.particle_texture = CHARGE_PARTICLE_TEX
	burst.particle_size = Vector2(8, 8)
	burst.particle_count = 44
	burst.particle_radius = 1.25
	burst.lifetime_seconds = 0.55
	burst.speed_min = 110.0
	burst.speed_max = 190.0
	burst.bounce_damping = 0.90
	add_child(burst)
	burst.start(bounds, int(Time.get_ticks_msec()) + stage_idx * 1337)

func _burst_room_particles_full() -> void:
	if _maze == null:
		_maze = get_tree().get_first_node_in_group("maze") as DungeonMazeLayer
		if _maze == null:
			_maze = get_node_or_null("../TileMap/MazeLayer") as DungeonMazeLayer
	if _maze == null:
		return

	var bounds := _room_bounds_world(_maze, room_rect)
	if bounds.size == Vector2.ZERO:
		return

	var burst := RoomBounceBurst.new()
	burst.set_as_top_level(true)
	burst.global_position = Vector2.ZERO
	burst.particle_texture = CHARGE_PARTICLE_TEX
	burst.particle_size = Vector2(14, 14)
	burst.particle_count = 160
	burst.particle_radius = 2.05
	burst.lifetime_seconds = 1.10
	burst.speed_min = 180.0
	burst.speed_max = 320.0
	burst.bounce_damping = 0.92
	add_child(burst)
	burst.start(bounds, int(Time.get_ticks_msec()) + 99991)

func _room_bounds_world(maze: DungeonMazeLayer, rect: Rect2i) -> Rect2:
	if rect.size == Vector2i.ZERO:
		return Rect2()
	if maze == null:
		return Rect2()
	var ts := maze.tile_set
	if ts == null:
		return Rect2()
	var tile := Vector2(ts.tile_size)
	if tile == Vector2.ZERO:
		return Rect2()

	var tl_cell := rect.position
	var br_cell := rect.end - Vector2i.ONE
	var tl_world := maze.to_global(maze.map_to_local(tl_cell))
	var br_world := maze.to_global(maze.map_to_local(br_cell))
	var half := tile * 0.5
	var min_world := Vector2(min(tl_world.x, br_world.x), min(tl_world.y, br_world.y)) - half
	var max_world := Vector2(max(tl_world.x, br_world.x), max(tl_world.y, br_world.y)) + half

	# Slightly inset so the bounce visually "bumps" inside the wall.
	var inset := 1.5
	var pos := min_world + Vector2(inset, inset)
	var size := (max_world - min_world) - Vector2(inset * 2.0, inset * 2.0)
	return Rect2(pos, Vector2(max(1.0, size.x), max(1.0, size.y)))
