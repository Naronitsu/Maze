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
var _completed: bool = false

var _charge_loop_player: AudioStreamPlayer2D
var _charge_stage_player: AudioStreamPlayer2D
var _charge_finish_player: AudioStreamPlayer2D
var _charge_fade_tween: Tween



# Powerup system
const POWERUP_SPRITE_PATH = "res://sprites/powerups/powerup.png"
const POWERUP_SPRITE_SIZE = Vector2i(32, 32)
const POWERUP_TYPES = [
	{
		"type": "vision",
		"region": Rect2(0, 0, 32, 32),
		"desc": "Vision Boost"
	},
	{
		"type": "move_speed",
		"region": Rect2(32, 0, 32, 32),
		"desc": "Move Speed"
	},
	{
		"type": "charge_speed",
		"region": Rect2(64, 0, 32, 32),
		"desc": "Charge Speed"
	}
]

var powerup_idx: int = -1
var powerup_data: Dictionary

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var particles: GPUParticles2D = $GPUParticles2D

# Call this to trigger a burst effect
func play_pillar_particles():
	if particles:
		particles.emitting = false
		particles.restart()
		particles.emitting = true

func _ready() -> void:
	add_to_group("pillars")
	set_process(false)
	if sprite != null:
		_set_idle_visual()
	_setup_audio()
	EventBus.player_moved.connect(_on_player_moved)

	# Pick a random powerup for this pillar
	powerup_idx = randi() % POWERUP_TYPES.size()
	powerup_data = POWERUP_TYPES[powerup_idx]

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

func is_completed() -> bool:
	return _completed

func _reset_charge() -> void:
	_started_charging = false
	_charge_elapsed = 0.0
	_last_stage_idx = 0
	_full_charge_burst_fired = false
	_completed = false
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
			if particles:
				# Ensure emission shape is circle, radius small for minor bursts
				var mat := particles.process_material
				if mat and mat is ParticleProcessMaterial:
					mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
					mat.emission_sphere_radius = 32.0
				particles.amount = 64
				particles.one_shot = true
				particles.emitting = false
				particles.restart()
				particles.emitting = true

	sprite.animation = charging_anim_name
	sprite.stop()
	sprite.frame = idx

	if _charge_elapsed >= duration:
		if not _full_charge_burst_fired:
			_full_charge_burst_fired = true
			_completed = true
			_play_charge_finish_sfx()
			if particles:
				# Make the final burst larger
				var mat := particles.process_material
				if mat and mat is ParticleProcessMaterial:
					mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
					mat.emission_sphere_radius = 64.0
				particles.amount = 160
				particles.one_shot = true
				particles.emitting = false
				particles.restart()
				particles.emitting = true

			# Apply powerup to player
			_apply_powerup_to_player()
			_stop_charge_loop_fade_out()
		set_process(false)

func _apply_powerup_to_player():
	# Find player node
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	# Track shrine charges globally
	GameConfig.shrines_charged += 1

	# On first shrine charged, emit signal to spawn Presence and set slow speed
	if GameConfig.shrines_charged == 1:
		EventBus.emit_signal("presence_should_spawn", [])
		GameConfig.presence_move_interval = 1.2 # Slow initial speed
		print("[Pillar] First shrine charged: Presence spawned, speed slow.")
	elif GameConfig.shrines_charged > 1:
		# Linearly interpolate speed from slow to normal as more shrines are charged
		var min_speed = 0.35 # Fastest
		var max_speed = 1.2  # Slowest
		var normal_speed = 0.45 # Current normal
		var total_shrines = 3 # Adjust if more shrines possible
		var t = float(GameConfig.shrines_charged - 1) / float(max(1, total_shrines - 1))
		GameConfig.presence_move_interval = lerp(max_speed, normal_speed, t)
		if GameConfig.presence_move_interval < min_speed:
			GameConfig.presence_move_interval = min_speed
		print("[Pillar] Shrine charged: Presence speed now %f" % GameConfig.presence_move_interval)

	# Apply effect and persist
	var save = SaveManager.current_save_data
	if not save.has("powerups"):
		save["powerups"] = []

	var ptype = powerup_data["type"]
	if ptype == "vision":
		# Increase vision range globally
		if not save.has("fog_vision_range_base"):
			save["fog_vision_range_base"] = GameConfig.fog_vision_range
		GameConfig.fog_vision_range = GameConfig.fog_vision_range + 8
	elif ptype == "move_speed":
		if not save.has("player_step_time_base"):
			save["player_step_time_base"] = GameConfig.player_step_time
		GameConfig.player_step_time = GameConfig.player_step_time - 0.03
	elif ptype == "charge_speed":
		if not save.has("pillar_charge_time_base"):
			save["pillar_charge_time_base"] = GameConfig.pillar_charge_time_seconds
		GameConfig.pillar_charge_time_seconds = GameConfig.pillar_charge_time_seconds - 0.5

	# Save powerup for persistence
	if not ptype in save["powerups"]:
		save["powerups"].append(ptype)
	SaveManager.current_save_data = save
	var player_cell = Vector2i.ZERO
	if save.has("player_cell"):
		if typeof(save["player_cell"]) == TYPE_VECTOR2I:
			player_cell = save["player_cell"]
		elif typeof(save["player_cell"]) == TYPE_DICTIONARY:
			var pc = save["player_cell"]
			player_cell = Vector2i(pc.get("x", 0), pc.get("y", 0))
	SaveManager.save_game(
		save.get("level", 1),
		save.get("run", 1),
		player_cell,
		save.get("maze_seed", 0),
		save.get("fog_path", ""),
		save.get("fog_size", Vector2i.ZERO)
	)

	# Show floating icon above player (fade-out sprite)
	var fade_scene = preload("res://scenes/gameplay/powerup_fade_sprite.tscn")
	var fade = fade_scene.instantiate()
	var anim_sprite = fade.get_node_or_null("AnimatedSprite2D")
	if anim_sprite:
		# Choose animation name based on powerup type
		var anim_name = "default"
		if powerup_data.has("type"):
			match powerup_data["type"]:
				"move_speed":
					anim_name = "move_speed"
				"charge_speed":
					anim_name = "charge_speed"
				"vision":
					anim_name = "vision_buff"
		anim_sprite.animation = anim_name
		anim_sprite.play()
	# Attach to PowerupAnchor if present, else fallback to player
	var anchor = player.get_node_or_null("PowerupAnchor")
	if anchor:
		fade.position = Vector2.ZERO
		anchor.add_child(fade)
	else:
		fade.position = Vector2(0, -48)
		player.add_child(fade)
	var fadeout = fade.create_tween()
	fadeout.tween_property(fade, "modulate:a", 0.0, 1.2)
	fadeout.tween_callback(fade.queue_free)


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
