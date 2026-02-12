extends Node
class_name AnimationController

signal sequence_finished(sequence_id: StringName)

@export var animated_sprite_path: NodePath

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null(animated_sprite_path) as AnimatedSprite2D

var _sequence_id: StringName = &""
var _duration: float = 0.0
var _elapsed: float = 0.0
var _playing: bool = false
var _anim_name: StringName = &""
var _hold_last_frame: bool = false

enum Mode { NONE, SCALED_PLAY, PROGRESS_STEPS }
var _mode: Mode = Mode.NONE
var _steps: int = 0

func _ready() -> void:
	set_process(false)
	if animated_sprite == null and animated_sprite_path != NodePath():
		animated_sprite = get_node_or_null(animated_sprite_path) as AnimatedSprite2D

func play_anim(anim_name: StringName, duration_seconds: float, sequence_id: StringName = &"", hold_last_frame: bool = true) -> void:
	if animated_sprite == null:
		return
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		return

	_anim_name = anim_name
	_sequence_id = sequence_id
	_hold_last_frame = hold_last_frame
	_duration = maxf(duration_seconds, 0.001)
	_elapsed = 0.0
	_playing = true
	_mode = Mode.SCALED_PLAY
	set_process(true)

	# Speed scaling so the animation finishes in duration_seconds.
	var frames := animated_sprite.sprite_frames.get_frame_count(anim_name)
	var base_fps := animated_sprite.sprite_frames.get_animation_speed(anim_name)
	if base_fps <= 0.0:
		base_fps = 1.0
	var desired_fps := float(frames) / _duration
	animated_sprite.speed_scale = desired_fps / base_fps
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()

func play_progress_steps(anim_name: StringName, steps: int, duration_seconds: float, sequence_id: StringName = &"", hold_last_frame: bool = true) -> void:
	if animated_sprite == null:
		return
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		return

	_anim_name = anim_name
	_sequence_id = sequence_id
	_hold_last_frame = hold_last_frame
	_duration = maxf(duration_seconds, 0.001)
	_elapsed = 0.0
	_playing = true
	_mode = Mode.PROGRESS_STEPS
	_steps = max(1, steps)
	set_process(true)

	animated_sprite.speed_scale = 1.0
	animated_sprite.animation = anim_name
	animated_sprite.stop()
	animated_sprite.frame = 0

func stop() -> void:
	_playing = false
	_elapsed = 0.0
	_anim_name = &""
	_mode = Mode.NONE
	_steps = 0
	set_process(false)

func is_playing() -> bool:
	return _playing

func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if animated_sprite != null and _anim_name != &"" and _mode == Mode.PROGRESS_STEPS:
		var frame_count := animated_sprite.sprite_frames.get_frame_count(_anim_name)
		if frame_count > 0:
			var desired := _steps
			if frame_count != desired and OS.is_debug_build():
				push_warning("[AnimationController] '%s' has %d frames; expected %d for stepped progress" % [_anim_name, frame_count, desired])
			var steps_used: int = min(desired, frame_count)
			var t := clampf(_elapsed / _duration, 0.0, 1.0)
			var idx := int(floor(t * float(steps_used)))
			idx = clampi(idx, 0, steps_used - 1)
			animated_sprite.frame = idx

	if _elapsed < _duration:
		return

	_playing = false
	set_process(false)
	if animated_sprite != null and _anim_name != &"":
		animated_sprite.stop()
		if _hold_last_frame and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(_anim_name):
			animated_sprite.frame = max(0, animated_sprite.sprite_frames.get_frame_count(_anim_name) - 1)

	emit_signal("sequence_finished", _sequence_id)
