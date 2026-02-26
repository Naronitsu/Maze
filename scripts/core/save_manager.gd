extends Node

## SaveManager autoload - handles game save/load persistence.
## Saves current run state (level, run number, player position) to disk.

#region Constants
const SAVE_FILE_PATH: String = "user://save_data.json"
const RUN_WON_FILE_PATH: String = "user://run_won.txt"
const FOG_SAVE_PATH: String = "user://fog_explored.png"
const INVALID_CELL: Vector2i = Vector2i(-999999, -999999)
#endregion

#region Public Properties
var current_save_data: Dictionary = {
	"level": 1,
	"run": 1,
	"player_cell": Vector2i.ZERO,
	"maze_seed": 0,
	"timestamp": 0,
	"fog_path": "",
	"fog_size": Vector2i.ZERO
}
#endregion

#region Private Fields
var _auto_save_enabled: bool = true
#endregion


#region Lifecycle
func _ready() -> void:
	add_to_group("persist")
	EventBus.level_started.connect(_on_level_started)
	EventBus.presence_caught_player.connect(_on_player_caught)
	EventBus.game_won.connect(_on_game_won)


#endregion


#region Public Methods
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_FILE_PATH)


func save_game(
	level: int,
	run: int,
	player_cell: Vector2i = Vector2i.ZERO,
	maze_seed: int = 0,
	fog_path: String = "",
	fog_size: Vector2i = Vector2i.ZERO,
	player_stats: Dictionary = {}
) -> bool:
	var fog_size_dict: Dictionary = {"w": fog_size.x, "h": fog_size.y}
	var save_dict: Dictionary = {
		"level": level,
		"run": run,
		"player_cell": {"x": player_cell.x, "y": player_cell.y},
		"maze_seed": maze_seed,
		"timestamp": Time.get_unix_time_from_system(),
		"fog_path": fog_path,
		"fog_size": fog_size_dict,
		"player_stats": player_stats
	}

	var json_string: String = JSON.stringify(save_dict, "\t")
	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: Failed to open save file for writing")
		return false

	file.store_string(json_string)
	file.close()

	current_save_data = save_dict
	current_save_data.fog_path = fog_path
	current_save_data.fog_size = fog_size
	print("[SaveManager] Game saved: Level %d, Run %d" % [level, run])
	return true


func load_game() -> Dictionary:
	if not has_save():
		print("[SaveManager] No save file found")
		return {}

	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: Failed to open save file for reading")
		return {}

	var json_string: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_string)
	if parse_result != OK:
		push_error("SaveManager: Failed to parse save file JSON")
		return {}

	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("SaveManager: Save file is not a dictionary")
		return {}

	# Restore native types
	if data.has("player_cell") and typeof(data.player_cell) == TYPE_DICTIONARY:
		var pc: Dictionary = data.player_cell
		data.player_cell = Vector2i(pc.get("x", 0), pc.get("y", 0))
	else:
		data.player_cell = Vector2i.ZERO

	if data.has("fog_size") and typeof(data.fog_size) == TYPE_DICTIONARY:
		var fs: Dictionary = data.fog_size
		data.fog_size = Vector2i(fs.get("w", 0), fs.get("h", 0))
	else:
		data.fog_size = Vector2i.ZERO

	current_save_data = data
	print(
		(
			"[SaveManager] Game loaded: Level %d, Run %d, Position: %s"
			% [data.get("level", 1), data.get("run", 1), data.get("player_cell", Vector2i.ZERO)]
		)
	)
	return data


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_FILE_PATH)
		print("[SaveManager] Save file deleted")

	current_save_data = {
		"level": 1,
		"run": 1,
		"player_cell": Vector2i.ZERO,
		"maze_seed": 0,
		"timestamp": 0,
		"fog_path": "",
		"fog_size": Vector2i.ZERO
	}


func get_save_info() -> Dictionary:
	if not has_save():
		return {}
	return load_game()


func save_player_stats(stats: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(RUN_WON_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(stats)
		file.close()
		print("[SaveManager] Player stats saved to %s" % RUN_WON_FILE_PATH)
	else:
		push_error("[SaveManager] Failed to save player stats to %s" % RUN_WON_FILE_PATH)


func check_for_win() -> bool:
	return FileAccess.file_exists(RUN_WON_FILE_PATH)


func load_previous_win_stats() -> Dictionary:
	if not check_for_win():
		return {}
	var file: FileAccess = FileAccess.open(RUN_WON_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Failed to load player stats from %s" % RUN_WON_FILE_PATH)
		return {}
	var stats: Variant = file.get_var()
	file.close()
	print("[SaveManager] Loaded previous win stats: %s" % str(stats))
	return stats if stats is Dictionary else {}


#endregion


#region Signal Handlers
func _on_level_started(player_pos: Vector2i, maze: Node) -> void:
	if not _auto_save_enabled:
		return
	if maze == null or not "level" in maze or not "run" in maze or not "rng_seed" in maze:
		return
	var fog_path: String = current_save_data.get("fog_path", "")
	var fog_size_val: Variant = current_save_data.get("fog_size", Vector2i.ZERO)
	var fog_size: Vector2i = Vector2i.ZERO
	if fog_size_val is Vector2i:
		fog_size = fog_size_val
	elif typeof(fog_size_val) == TYPE_DICTIONARY:
		fog_size = Vector2i(fog_size_val.get("w", 0), fog_size_val.get("h", 0))
	save_game(maze.level, maze.run, player_pos, maze.rng_seed, fog_path, fog_size)


func _on_player_caught(_presence_cell: Vector2i, _player_cell: Vector2i) -> void:
	delete_save()
	print("[SaveManager] Run ended - save deleted")


func _on_game_won() -> void:
	save_player_stats(current_save_data.get("player_stats", {}))
#endregion
