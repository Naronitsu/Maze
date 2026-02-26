extends Node
class_name AudioManager

## Plays spatial audio for doors and presence; subscribes to EventBus.

#region Exported (Inspector)
@export var maze_path: NodePath
@export var door_open_stream: AudioStream
@export var door_close_stream: AudioStream
@export var presence_sound_stream: AudioStream
@export_group("Tuning")
@export var sfx_bus: StringName = &"SFX"
@export var default_max_distance: float = 500.0
@export var default_attenuation: float = 1.0
#endregion

#region Onready
@onready var maze: DungeonMazeLayer = get_node_or_null(maze_path) as DungeonMazeLayer
#endregion

#region Lifecycle
func _ready() -> void:
	# Subscribe to EventBus signals
	EventBus.door_opened.connect(_on_door_opened)
	EventBus.door_closed.connect(_on_door_closed)
	EventBus.presence_moved.connect(_on_presence_moved)

	# Also keep direct maze connection as fallback
	if maze != null:
		if not maze.door_opened.is_connected(_on_door_opened):
			maze.door_opened.connect(_on_door_opened)
		if not maze.door_closed.is_connected(_on_door_closed):
			maze.door_closed.connect(_on_door_closed)
#endregion

#region Signal Handlers
func _on_door_opened(cell: Vector2i) -> void:
	_play_spatial_at_cell(door_open_stream, cell)


func _on_door_closed(cell: Vector2i) -> void:
	_play_spatial_at_cell(door_close_stream, cell)


func _on_presence_moved(_from_cell: Vector2i, to_cell: Vector2i) -> void:
	# Play presence sound with randomized position offset
	if presence_sound_stream != null and maze != null:
		var base_pos = maze.to_global(maze.map_to_local(to_cell))
		var offset = Vector2(randf_range(-96, 96), randf_range(-96, 96))
		_play_spatial_at_position(presence_sound_stream, base_pos + offset, 0.92, 1.08)
#endregion

#region Private Methods
func _play_spatial_at_cell(stream: AudioStream, cell: Vector2i) -> void:
	if stream == null or maze == null:
		return

	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.bus = sfx_bus
	p.max_distance = default_max_distance
	p.attenuation = default_attenuation

	# Place at door center (world space)
	p.global_position = maze.to_global(maze.map_to_local(cell))

	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _play_spatial_at_position(
	stream: AudioStream, pos: Vector2, pitch_min: float = 1.0, pitch_max: float = 1.0
) -> void:
	if stream == null:
		return

	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.bus = sfx_bus
	p.max_distance = default_max_distance
	p.attenuation = default_attenuation
	p.pitch_scale = randf_range(pitch_min, pitch_max)
	p.global_position = pos

	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
#endregion
