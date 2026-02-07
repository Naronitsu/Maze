extends Node
## Simplified level transition manager - delegates to TransitionController
## This now just listens to level_transitioning signal and forwards to controller

var game: Node2D
var transition_controller: Node

func _ready() -> void:
	# Get references
	game = get_parent() if get_parent() is Node2D else null
	
	# Subscribe to level transitioning event
	EventBus.level_transitioning.connect(_on_level_transitioning)

func _on_level_transitioning() -> void:
	# Defer lookup to ensure transition_controller is available
	if game == null:
		game = get_parent() if get_parent() is Node2D else null
	
	if game == null:
		push_error("[LevelTransitionManager] game parent not found")
		return
	
	transition_controller = game.transition_controller if game else null
	
	if transition_controller == null:
		push_error("[LevelTransitionManager] transition_controller not set")
		return
	
	transition_controller.start_transition()
