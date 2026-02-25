extends CanvasLayer

@onready var heartbeat_audio: AudioStreamPlayer2D = $HeartbeatAudio
@onready var veins: TextureRect = $Veins

# Will be set by game.gd
var vision_controller: VisionController = null
var fog: Node = null

var _veins_tween: Tween
var _cam_tween: Tween

var _timer: float = 0.0
var _period: float = 1.0


func _ready() -> void:
	if veins:
		veins.modulate.a = 0.0
		veins.scale = Vector2.ONE
	_update_period()


func _process(delta: float) -> void:
	_update_period()
	_apply_base_pressure()

	_timer += delta
	if _timer >= _period:
		_timer -= _period
		_pulse_once()


# NEW: pressure from VisionController
func _get_pressure01() -> float:
	if vision_controller == null:
		return 0.0
	return clampf(vision_controller.get_pressure01(), 0.0, 1.0)


func _update_period() -> void:
	var a := _get_pressure01()
	# calmer early, intense late
	var bpm := lerpf(GameConfig.heartbeat_bpm_min, GameConfig.heartbeat_bpm_max, a * a)
	_period = 60.0 / maxf(1.0, bpm)


func _apply_base_pressure() -> void:
	if veins == null:
		return

	var a := _get_pressure01()
	var base := lerpf(0.0, GameConfig.heartbeat_veins_base_alpha_max, a * a)

	if veins.modulate.a < base:
		veins.modulate.a = base


func _pulse_once() -> void:
	if veins == null:
		return

	var a := _get_pressure01()

	var peak_alpha := lerpf(
		GameConfig.heartbeat_veins_alpha_min, GameConfig.heartbeat_veins_alpha_max, a * a
	)
	var peak_scale := lerpf(
		GameConfig.heartbeat_veins_scale_min, GameConfig.heartbeat_veins_scale_max, a * a
	)
	var dub_alpha := peak_alpha * 0.65
	var dub_scale := lerpf(1.0, peak_scale, 0.65)

	if _veins_tween and _veins_tween.is_running():
		_veins_tween.kill()
	if _cam_tween and _cam_tween.is_running():
		_cam_tween.kill()

	veins.modulate.a = 0.0
	veins.scale = Vector2.ONE

	_veins_tween = create_tween()
	_veins_tween.set_trans(Tween.TRANS_SINE)
	_veins_tween.set_ease(Tween.EASE_OUT)

	# LUB
	_veins_tween.tween_property(veins, "modulate:a", peak_alpha, GameConfig.heartbeat_beat_fade_in)
	_veins_tween.parallel().tween_property(
		veins, "scale", Vector2(peak_scale, peak_scale), GameConfig.heartbeat_beat_fade_in
	)

	_veins_tween.tween_property(veins, "modulate:a", 0.0, GameConfig.heartbeat_beat_fade_out)
	_veins_tween.parallel().tween_property(
		veins, "scale", Vector2.ONE, GameConfig.heartbeat_beat_fade_out
	)

	# DUB
	_veins_tween.tween_interval(GameConfig.heartbeat_dub_delay)
	_veins_tween.tween_property(veins, "modulate:a", dub_alpha, GameConfig.heartbeat_beat_fade_in)
	_veins_tween.parallel().tween_property(
		veins, "scale", Vector2(dub_scale, dub_scale), GameConfig.heartbeat_beat_fade_in
	)

	_veins_tween.tween_property(veins, "modulate:a", 0.0, GameConfig.heartbeat_beat_fade_out)
	_veins_tween.parallel().tween_property(
		veins, "scale", Vector2.ONE, GameConfig.heartbeat_beat_fade_out
	)

	_play_heartbeat()

	var cam := get_viewport().get_camera_2d()
	if cam:
		var z0 := cam.zoom
		var z1 := (
			z0 * Vector2(GameConfig.heartbeat_cam_thump_zoom, GameConfig.heartbeat_cam_thump_zoom)
		)

		_cam_tween = create_tween()
		_cam_tween.tween_property(cam, "zoom", z1, GameConfig.heartbeat_cam_thump_in)
		_cam_tween.tween_property(cam, "zoom", z0, GameConfig.heartbeat_cam_thump_out)


func _play_heartbeat() -> void:
	if heartbeat_audio == null or heartbeat_audio.stream == null:
		return
	heartbeat_audio.stop()
	heartbeat_audio.play()
