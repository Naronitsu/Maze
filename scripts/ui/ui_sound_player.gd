## UI Sound Player singleton for button hover/select sounds
extends Node

var hover_stream: AudioStream = preload("res://sounds/ui_hover.sfxr")
var select_stream: AudioStream = preload("res://sounds/ui_select.sfxr")

var hover_player: AudioStreamPlayer
var select_player: AudioStreamPlayer

func _ready() -> void:
	# Create and add AudioStreamPlayers
	hover_player = AudioStreamPlayer.new()
	hover_player.stream = hover_stream
	hover_player.bus = "SFX"
	add_child(hover_player)

	select_player = AudioStreamPlayer.new()
	select_player.stream = select_stream
	select_player.bus = "SFX"
	add_child(select_player)

func play_hover() -> void:
	hover_player.play()

func play_select() -> void:
	select_player.play()
