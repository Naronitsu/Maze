extends Node2D
signal finished


@onready var grab_pos_node: Node2D = $grabPosition
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _player: Node2D = null
var _minigame: Node = null

@export var max_grab_time := 3.0

@export var grab_zoom_multiplier := 1.7 # >1 zooms IN

@export var zoom_time := 0.25

var _camera: Camera2D = null
var _original_zoom: Vector2
var _original_offset: Vector2

func init_grab(player: Node2D, spawn_world: Vector2) -> void:
	_player = player
	global_position = spawn_world

func _ready() -> void:
	sprite.play("spawn")
	await sprite.animation_finished
	call_deferred("_do_grab")

func _do_grab() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		push_error("[GrabAttack] Player not found")
		_end_grab()
		return


	var p := grab_pos_node.global_position
	_player.movement_locked = true
	_player.global_position = p

	# Switch to idle animation after anchoring player
	sprite.play("idle")

	_camera = _player.get_node_or_null("Camera") as Camera2D
	if _camera:
		_original_zoom = _camera.zoom
		_original_offset = _camera.offset
		_camera.offset = Vector2(randf_range(-4,4), randf_range(-4,4))

		var target_zoom := _original_zoom * grab_zoom_multiplier

		var tween := create_tween()
		tween.tween_property(_camera, "zoom", target_zoom, zoom_time)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_OUT)


	_minigame = get_tree().current_scene.get_node_or_null("UI/grabMinigame")
	if _minigame == null:
		push_warning("[GrabAttack] UI/grabMinigame not found")
	else:
		if _minigame.has_method("start_follow"):
			_minigame.call("start_follow", _player)

		if _minigame.has_method("show_message"):
			_minigame.call("show_message", "YOU HAVE BEEN GRABBED!")
		await get_tree().create_timer(0.75).timeout

		if _minigame.has_method("hide_message"):
			_minigame.call("hide_message")

		if _minigame.has_method("start"):
			_minigame.call("start")

		if _minigame.has_signal("escaped"):
			_minigame.connect("escaped", Callable(self, "_on_minigame_escaped"), CONNECT_ONE_SHOT)
		if _minigame.has_signal("failed"):
			_minigame.connect("failed", Callable(self, "_on_minigame_failed"), CONNECT_ONE_SHOT)

	await get_tree().create_timer(max_grab_time).timeout
	if is_inside_tree():
		_end_grab()

func _on_minigame_escaped() -> void:
	_end_grab()

func _on_minigame_failed() -> void:
	_player.call("_take_damage", 1)
	_end_grab()

var _ending := false

func _end_grab() -> void:
	if _ending:
		return
	_ending = true

	if _minigame:
		if _minigame.has_method("stop"):
			_minigame.call("stop")
		if _minigame.has_method("stop_follow"):
			_minigame.call("stop_follow")

	if _player:
		_player.movement_locked = false

	if _camera:
		_camera.offset = _original_offset

		var tween := _camera.create_tween()
		tween.tween_property(_camera, "zoom", _original_zoom, zoom_time)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN)

		await tween.finished

	# Play despawn animation before finishing
	sprite.play("despawn")
	await sprite.animation_finished

	finished.emit()
	queue_free()
