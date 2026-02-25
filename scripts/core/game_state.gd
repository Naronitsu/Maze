extends Node
## Centralized game state management.
## Use GameState.current to check/set game state instead of scattered flags.

enum State { PLAYING, TRANSITIONING, LEVEL_UP, PAUSED, GAME_OVER, GAME_WON }  # Normal gameplay  # Between levels  # Level up screen  # Player paused  # Player caught  # Player won the game

var current: State = State.PLAYING:
	set(value):
		if value != current:
			var prev = current
			current = value
			var prev_name = State.keys()[prev]
			var new_name = State.keys()[value]
			print("[GameState] Transition: %s -> %s" % [prev_name, new_name])
			_emit_state_change(prev, value)


func _ready() -> void:
	add_to_group("persist")  # Singleton pattern


func _emit_state_change(from_state: State, to_state: State) -> void:
	var from_name = State.keys()[from_state]
	var to_name = State.keys()[to_state]

	EventBus.state_changed.emit(from_name, to_name)


func is_playing() -> bool:
	return current == State.PLAYING


func is_transitioning() -> bool:
	return current == State.TRANSITIONING
