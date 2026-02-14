extends Node

func _ready():
	await SceneLoader.change_scene_with_loading("res://scenes/ui/main_menu.tscn")
