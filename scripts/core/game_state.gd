extends Node

## Centralized game state management.
## Use GameState.current to check/set game state instead of scattered flags.

#region Constants
enum State { PLAYING, TRANSITIONING, LEVEL_UP, PAUSED, GAME_OVER, GAME_WON }
#endregion

#region Public Properties
var current: State = State.PLAYING:
	set(value):
		if value != current:
			var prev := current
			current = value
			print("[GameState] Transition: %s -> %s" % [State.keys()[prev], State.keys()[value]])
			_emit_state_change(prev, value)
#endregion


#region Lifecycle
func _ready() -> void:
	add_to_group("persist")


#endregion


#region Public Methods
func is_playing() -> bool:
	return current == State.PLAYING


func is_transitioning() -> bool:
	return current == State.TRANSITIONING


#endregion


#region Private Methods
func _emit_state_change(from_state: State, to_state: State) -> void:
	var from_name: String = State.keys()[from_state]
	var to_name: String = State.keys()[to_state]
	EventBus.state_changed.emit(from_name, to_name)
#endregion
