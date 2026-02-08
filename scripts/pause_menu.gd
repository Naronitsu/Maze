extends Control

signal resume_pressed
signal settings_pressed
signal quit_pressed

@onready var resume_button: Button = $Center/Panel/VBox/ResumeButton
@onready var settings_button: Button = $Center/Panel/VBox/SettingsButton
@onready var quit_button: Button = $Center/Panel/VBox/QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_resume_pressed() -> void:
	resume_pressed.emit()

func _on_settings_pressed() -> void:
	settings_pressed.emit()

func _on_quit_pressed() -> void:
	quit_pressed.emit()
