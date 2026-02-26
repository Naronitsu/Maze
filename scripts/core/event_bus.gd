extends Node

## Central event hub for all game communications.
## Use this instead of direct method calls to decouple systems.

#region Signals
# Level lifecycle
signal level_started(spawn_cell: Vector2i, maze: DungeonMazeLayer)
signal level_transitioning
signal level_ended
signal game_over
signal game_won

# Player events
signal player_moved(from_cell: Vector2i, to_cell: Vector2i)
signal player_closed_eyes
signal player_opened_eyes
signal player_health_changed(current: float, max: float)

# Presence events
signal presence_should_spawn(player_history: Array)
signal presence_spawned(cell: Vector2i)
signal presence_moved(from_cell: Vector2i, to_cell: Vector2i)
signal presence_caught_player(presence_cell: Vector2i, player_cell: Vector2i)
signal presence_flicker

# Door events
signal door_opened(cell: Vector2i)
signal door_closed(cell: Vector2i)
signal door_interacted(cell: Vector2i)

# Game state events
signal state_changed(from_state: String, to_state: String)
signal pause_requested
signal resume_requested
signal return_to_menu_requested

# UI
signal minimap_size_changed(size: Vector2)
#endregion

#region Lifecycle
func _ready() -> void:
	add_to_group("persist")
#endregion
