extends Node2D

@export var max_levels_before_reset: int = 10

@onready var maze: MazeLayer = $TileMap/MazeLayer
@onready var player: CharacterBody2D = $Player

var _transitioning: bool = false

func _ready() -> void:
	_start_new_level(maze.generate())

func _physics_process(_delta: float) -> void:
	if _transitioning:
		return

	# Only works if player has `cell: Vector2i`
	if not ("cell" in player):
		return

	if (player.cell as Vector2i) == maze.exit_cell:
		_transitioning = true
		call_deferred("_advance_and_restart")

func _advance_and_restart() -> void:
	var info: Dictionary
	if maze.level >= max_levels_before_reset:
		info = maze.advance_run()
	else:
		info = maze.advance_level()

	_start_new_level(info)

	# allow future transitions after we’ve moved off the exit
	_transitioning = false

func _start_new_level(info: Dictionary) -> void:
	var start: Vector2i = info["start"] as Vector2i

	# If your player script uses a TileMap reference, keep it synced
	if "maze_path" in player:
		player.maze_path = maze.get_path()

	# Prefer calling player's reset method (cancels in-progress movement)
	if player.has_method("reset_to_cell"):
		player.reset_to_cell(start)
	else:
		# fallback
		player.global_position = maze.cell_to_global(start)
		if "cell" in player:
			player.cell = start
