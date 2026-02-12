extends Node

const PILLAR_SCENE: PackedScene = preload("res://scenes/gameplay/pillar.tscn")

func _ready() -> void:
	EventBus.level_started.connect(_on_level_started)

func _on_level_started(spawn_cell: Vector2i, maze: DungeonMazeLayer) -> void:
	for n in get_tree().get_nodes_in_group("pillars"):
		if is_instance_valid(n):
			n.queue_free()

	if maze == null:
		return

	# Spawn pillars only in the smaller minor rooms. Leave the larger reward room empty.
	var room_rects: Array[Rect2i] = maze.get_minor_room_rects()
	for rect: Rect2i in room_rects:
		var center_cell := rect.position + Vector2i(rect.size.x / 2, rect.size.y / 2)
		var pillar := PILLAR_SCENE.instantiate() as Node2D
		add_child(pillar)
		pillar.global_position = maze.to_global(maze.map_to_local(center_cell))
		if pillar.has_method("setup"):
			pillar.call("setup", rect, spawn_cell, maze)
