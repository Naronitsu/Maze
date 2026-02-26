extends Node

## Entry point: redirects to main menu with loading overlay.

#region Lifecycle
func _ready() -> void:
	await SceneLoader.change_scene_with_loading("res://scenes/ui/main_menu.tscn")
#endregion
