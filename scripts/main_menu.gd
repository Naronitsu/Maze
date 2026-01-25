extends Control

@export var game_scene: PackedScene
@export var fade_out_time: float = 0.35

@onready var play_btn: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var quit_btn: Button = $CenterContainer/VBoxContainer/QuitButton

var _transitioning := false
var _fade_rect: ColorRect

func _ready() -> void:
	play_btn.pressed.connect(_on_play_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	# Create a guaranteed full-screen black overlay on top
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRectRuntime"
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = true
	_fade_rect.modulate.a = 0.0
	add_child(_fade_rect)

	# Ensure it fills the screen
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.offset_left = 0
	_fade_rect.offset_top = 0
	_fade_rect.offset_right = 0
	_fade_rect.offset_bottom = 0

	# Ensure it draws on top
	_fade_rect.z_index = 999

func _on_play_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true

	if game_scene == null:
		push_error("MainMenu: game_scene not assigned")
		_transitioning = false
		return

	play_btn.disabled = true
	quit_btn.disabled = true

	# Fade to black
	var t := create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, fade_out_time)

	await t.finished

	get_tree().change_scene_to_packed(game_scene)

func _on_quit_pressed() -> void:
	get_tree().quit()
