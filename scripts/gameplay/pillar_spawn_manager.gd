extends Node

## Spawns shrine pillars in minor rooms on level start; clears existing pillars first.

#region Constants
const PILLAR_SCENE: PackedScene = preload("res://scenes/gameplay/pillar.tscn")
#endregion


#region Lifecycle
func _ready() -> void:
	EventBus.level_started.connect(_on_level_started)


#endregion


#region Signal Handlers
func _on_level_started(spawn_cell: Vector2i, maze: DungeonMazeLayer) -> void:
	for n in get_tree().get_nodes_in_group("pillars"):
		if is_instance_valid(n):
			n.queue_free()

	if maze == null:
		return

	var room_rects: Array[Rect2i] = maze.get_minor_room_rects()
	for rect: Rect2i in room_rects:
		var center_cell: Vector2i = (
			rect.position + Vector2i(int(rect.size.x / 2.0), int(rect.size.y / 2.0))
		)
		var pillar: Node2D = PILLAR_SCENE.instantiate() as Node2D
		add_child(pillar)
		pillar.global_position = maze.to_global(maze.map_to_local(center_cell))
		if pillar.has_method("setup"):
			pillar.call("setup", rect, spawn_cell, maze)
#endregion
