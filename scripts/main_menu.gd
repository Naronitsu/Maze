extends Control

@export var game_scene: PackedScene
@export var fade_out_time: float = 0.35

@onready var continue_btn: Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var play_btn: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var quit_btn: Button = $CenterContainer/VBoxContainer/QuitButton

var _transitioning := false
var _fade_rect: ColorRect
var _is_continue := false

func _ready() -> void:
	continue_btn.pressed.connect(_on_continue_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	# Show/hide continue button based on save existence
	if SaveManager.has_save():
		var save_info = SaveManager.get_save_info()
		continue_btn.visible = true
		if "level" in save_info and "run" in save_info:
			continue_btn.text = "Continue (Level %d, Run %d)" % [save_info.level, save_info.run]
	else:
		continue_btn.visible = false

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

func _start_game() -> void:
	if _transitioning:
		return
	_transitioning = true

	if game_scene == null:
		push_error("MainMenu: game_scene not assigned")
		_transitioning = false
		return

	if continue_btn:
		continue_btn.disabled = true
	play_btn.disabled = true
	quit_btn.disabled = true

	# Fade to black
	var t := create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, fade_out_time)

	await t.finished

	# Load saved game if continuing
	if _is_continue:
		var save_data = SaveManager.load_game()
		# Store for game.gd to read on _ready
		SaveManager.current_save_data = save_data
		_is_continue = false

	get_tree().change_scene_to_packed(game_scene)

func _on_continue_pressed() -> void:
	_is_continue = true
	_start_game()

func _on_play_pressed() -> void:
	# Clear save data for new game
	SaveManager.current_save_data = {}
	_is_continue = false
	_start_game()

func _on_quit_pressed() -> void:
	get_tree().quit()
