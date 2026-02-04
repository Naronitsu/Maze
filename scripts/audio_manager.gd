# AudioManager.gd
extends Node
class_name AudioManager

@export var maze_path: NodePath

@export var door_open_stream: AudioStream
@export var door_close_stream: AudioStream

# Optional tuning
@export var sfx_bus: StringName = &"SFX"
@export var default_max_distance: float = 500.0
@export var default_attenuation: float = 1.0

@onready var maze: DungeonMazeLayer = get_node_or_null(maze_path) as DungeonMazeLayer

func _ready() -> void:
	if maze != null:
		maze.door_opened.connect(_on_door_opened)
		maze.door_closed.connect(_on_door_closed)

func _on_door_opened(cell: Vector2i) -> void:
	_play_spatial_at_cell(door_open_stream, cell)

func _on_door_closed(cell: Vector2i) -> void:
	_play_spatial_at_cell(door_close_stream, cell)

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
