extends Control

@export var game_scene: PackedScene

@onready var play_btn: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var quit_btn: Button = $CenterContainer/VBoxContainer/QuitButton

func _ready() -> void:
	if play_btn:
		play_btn.pressed.connect(_on_play_pressed)
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_pressed)

func _on_play_pressed() -> void:
	if game_scene == null:
		push_error("MainMenu: game_scene not assigned")
		return
	get_tree().change_scene_to_packed(game_scene)

func _on_quit_pressed() -> void:
	get_tree().quit()
