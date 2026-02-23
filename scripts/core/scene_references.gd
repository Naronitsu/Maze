extends Node
## SceneReferences autoload - centralized node path management
## Caches all critical scene references and validates them at runtime

var game: Node2D
var maze: Node
var player: Node2D
var presence: Node2D
var controller: Node
var camera: Camera2D
var fog: Node
var ui_layer: CanvasLayer
var level_intro_panel: ColorRect
var level_intro_text: Label
var level_up_panel: LevelUpPanel

func _ready() -> void:
	# This autoload runs BEFORE game.gd _ready() completes
	# We don't validate here; validation happens via validate_all()
	pass

## Call this from game._ready() once all nodes are guaranteed to exist
func validate_all(scene_root: Node2D) -> bool:
	game = scene_root
	
	# Cache references
	maze = game.get_node_or_null("TileMap/MazeLayer")
	player = game.get_node_or_null("Player")
	presence = game.get_node_or_null("PresenceRW")
	controller = game.get_node_or_null("GameController")
	camera = game.get_node_or_null("Player/Camera")
	fog = game.get_node_or_null("Overlay/FogOfWarRW")
	ui_layer = game.get_node_or_null("UI")
	level_intro_panel = game.get_node_or_null("UI/LevelIntro")
	level_intro_text = game.get_node_or_null("UI/LevelIntro/Text")
	level_up_panel = game.get_node_or_null("UI/LevelUpPanel")
	
	
	# Validate critical references
	var errors: PackedStringArray = []
	
	if maze == null:
		errors.append("maze (TileMap/MazeLayer)")
	if player == null:
		errors.append("player (Player)")
	if presence == null:
		errors.append("presence (PresenceRW)")
	if controller == null:
		errors.append("controller (GameController)")
	if camera == null:
		errors.append("camera (Player/Camera)")
	if fog == null:
		errors.append("fog (Overlay/FogOfWarRW)")
	if ui_layer == null:
		errors.append("ui_layer (UI)")
	if level_intro_panel == null:
		errors.append("level_intro_panel (UI/LevelIntro)")
	if level_intro_text == null:
		errors.append("level_intro_text (UI/LevelIntro/Text)")
	if level_up_panel == null:
		errors.append("level_up_panel (UI/LevelUpPanel)")
	
	if errors.size() > 0:
		push_error("[SceneReferences] Missing nodes: " + ", ".join(errors))
		return false
	
	print("[SceneReferences] All nodes validated successfully")
	return true

## Safe getter - returns null if not found
func get_safe(node_name: String) -> Node:
	match node_name:
		"game": return game
		"maze": return maze
		"player": return player
		"presence": return presence
		"controller": return controller
		"camera": return camera
		"fog": return fog
		"ui_layer": return ui_layer
		"level_intro_panel": return level_intro_panel
		"level_intro_text": return level_intro_text
		_:
			push_warning("[SceneReferences] Unknown node: " + node_name)
			return null
