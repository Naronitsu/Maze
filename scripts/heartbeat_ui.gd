# HeartbeatUI.gd
extends CanvasLayer

@export var presence_path: NodePath
@onready var presence: Node = get_node_or_null(presence_path)
@onready var heartbeat_audio: AudioStreamPlayer2D = $HeartbeatAudio

@onready var veins: TextureRect = $Veins

var _veins_tween: Tween
var _cam_tween: Tween

# Beat timing
@export var bpm_min: float = 48.0
@export var bpm_max: float = 140.0

# Veins strength (visibility)
@export var veins_alpha_min: float = 0.00
@export var veins_alpha_max: float = 0.55

# Optional persistent pressure between beats (keep small)
@export var veins_base_alpha_max: float = 0.18

# Veins "growth" toward the center
@export var veins_scale_min: float = 1.00
@export var veins_scale_max: float = 1.10

# Two-beat shape (lub-dub)
@export var dub_delay: float = 0.12
@export var beat_fade_in: float = 0.05
@export var beat_fade_out: float = 0.12

# Camera thump tuning
@export var cam_thump_zoom: float = 0.985
@export var cam_thump_in: float = 0.03
@export var cam_thump_out: float = 0.10

var _timer: float = 0.0
var _period: float = 1.0

func _ready() -> void:
	# Start invisible and unscaled
	if veins:
		veins.modulate.a = 0.0
		veins.scale = Vector2.ONE
	_update_period()

func _process(delta: float) -> void:
	_update_period()

	# Optional: faint persistent veins based on attention
	_apply_base_pressure()

	_timer += delta
	if _timer >= _period:
		_timer -= _period
		_pulse_once()

func _get_attention01() -> float:
	var att := 0.0
	if presence != null:
		var v: Variant = presence.get("attention")
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			att = float(v)
	return clampf(att / 100.0, 0.0, 1.0)

func _update_period() -> void:
	var a := _get_attention01()

	# Square keeps it calmer early, more intense late
	var bpm := lerpf(bpm_min, bpm_max, a * a)
	_period = 60.0 / maxf(1.0, bpm)

func _apply_base_pressure() -> void:
	if veins == null:
		return

	var a := _get_attention01()
	var base := lerpf(0.0, veins_base_alpha_max, a * a)

	# Don't fight the pulse tween: only raise the baseline if current alpha is lower
	if veins.modulate.a < base:
		veins.modulate.a = base

func _pulse_once() -> void:
	if veins == null:
		return

	var a := _get_attention01()

	# Make veins intensity and growth respond nonlinearly (feels more "alive")
	var peak_alpha := lerpf(veins_alpha_min, veins_alpha_max, a * a)
	var peak_scale := lerpf(veins_scale_min, veins_scale_max, a * a)
	var dub_alpha := peak_alpha * 0.65
	var dub_scale := lerpf(1.0, peak_scale, 0.65)

	# Kill previous tweens
	if _veins_tween and _veins_tween.is_running():
		_veins_tween.kill()
	if _cam_tween and _cam_tween.is_running():
		_cam_tween.kill()

	# Reset baseline before pulsing (prevents drift)
	# (Baseline pressure gets re-applied in _process)
	veins.modulate.a = 0.0
	veins.scale = Vector2.ONE

	_veins_tween = create_tween()
	_veins_tween.set_trans(Tween.TRANS_SINE)
	_veins_tween.set_ease(Tween.EASE_OUT)

	# LUB: appear + grow
	_veins_tween.tween_property(veins, "modulate:a", peak_alpha, beat_fade_in)
	_veins_tween.parallel().tween_property(veins, "scale", Vector2(peak_scale, peak_scale), beat_fade_in)

	# fade back
	_veins_tween.tween_property(veins, "modulate:a", 0.0, beat_fade_out)
	_veins_tween.parallel().tween_property(veins, "scale", Vector2.ONE, beat_fade_out)

	# DUB: smaller second beat
	_veins_tween.tween_interval(dub_delay)
	_veins_tween.tween_property(veins, "modulate:a", dub_alpha, beat_fade_in)
	_veins_tween.parallel().tween_property(veins, "scale", Vector2(dub_scale, dub_scale), beat_fade_in)

	_veins_tween.tween_property(veins, "modulate:a", 0.0, beat_fade_out)
	_veins_tween.parallel().tween_property(veins, "scale", Vector2.ONE, beat_fade_out)
	
	_play_heartbeat()

	# Camera thump (keep it)
	var cam := get_viewport().get_camera_2d()
	if cam:
		var z0 := cam.zoom
		var z1 := z0 * Vector2(cam_thump_zoom, cam_thump_zoom)

		_cam_tween = create_tween()
		_cam_tween.tween_property(cam, "zoom", z1, cam_thump_in)
		_cam_tween.tween_property(cam, "zoom", z0, cam_thump_out)
		

func _play_heartbeat() -> void:
	if heartbeat_audio == null or heartbeat_audio.stream == null:
		return
	heartbeat_audio.stop()
	heartbeat_audio.play()
	
	
