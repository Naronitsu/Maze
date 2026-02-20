extends Node
## SaveManager autoload - handles game save/load persistence.
## Saves current run state (level, run number, player position) to disk.

const SAVE_FILE_PATH = "user://save_data.json"
const RUN_WON_FILE_PATH = "user://run_won.txt"
const FOG_SAVE_PATH = "user://fog_explored.png"
const INVALID_CELL := Vector2i(-999999, -999999)

# Current run state
var current_save_data: Dictionary = {
	"level": 1,
	"run": 1,
	"player_cell": Vector2i.ZERO,
	"maze_seed": 0,
	"timestamp": 0,
	"fog_path": "",
	"fog_size": Vector2i.ZERO
}

var _auto_save_enabled: bool = true

func _ready() -> void:
	add_to_group("persist")
	
	# Subscribe to game events for auto-save
	EventBus.level_started.connect(_on_level_started)
	EventBus.presence_caught_player.connect(_on_player_caught)
	EventBus.game_won.connect(_on_game_won)

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
	var fog_size_dict := {"w": fog_size.x, "h": fog_size.y}

	var save_dict = {
		"level": level,
		"run": run,
		"player_cell": {"x": player_cell.x, "y": player_cell.y},
		"maze_seed": maze_seed,
		"timestamp": Time.get_unix_time_from_system(),
		"fog_path": fog_path,
		"fog_size": fog_size_dict,
		"player_stats": player_stats
	}
	
	var json_string = JSON.stringify(save_dict, "\t")
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	
	if file == null:
		push_error("SaveManager: Failed to open save file for writing")
		return false
	
	file.store_string(json_string)
	file.close()
	
	current_save_data = save_dict
	# Keep runtime copy in native types
	current_save_data.fog_path = fog_path
	current_save_data.fog_size = fog_size
	print("[SaveManager] Game saved: Level %d, Run %d" % [level, run])
	return true

func load_game() -> Dictionary:
	if not has_save():
		print("[SaveManager] No save file found")
		return {}
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	
	if file == null:
		push_error("SaveManager: Failed to open save file for reading")
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("SaveManager: Failed to parse save file JSON")
		return {}
	
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("SaveManager: Save file is not a dictionary")
		return {}
	
	# Convert player_cell dict back to Vector2i
	if data.has("player_cell") and typeof(data.player_cell) == TYPE_DICTIONARY:
		var pc = data.player_cell
		data.player_cell = Vector2i(pc.get("x", 0), pc.get("y", 0))
	else:
		data.player_cell = Vector2i.ZERO

	# Convert fog_size dict back to Vector2i
	if data.has("fog_size") and typeof(data.fog_size) == TYPE_DICTIONARY:
		var fs = data.fog_size
		data.fog_size = Vector2i(fs.get("w", 0), fs.get("h", 0))
	else:
		data.fog_size = Vector2i.ZERO
	
	current_save_data = data
	print("[SaveManager] Game loaded: Level %d, Run %d, Position: %s" % [data.get("level", 1), data.get("run", 1), data.get("player_cell", Vector2i.ZERO)])
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

# Auto-save on level completion
func _on_level_started(player_pos: Vector2i, maze: Node) -> void:
	if not _auto_save_enabled:
		return
	
	if maze and "level" in maze and "run" in maze and "rng_seed" in maze:
		var fog_path: String = current_save_data.get("fog_path", "")
		var fog_size_val: Variant = current_save_data.get("fog_size", Vector2i.ZERO)
		var fog_size: Vector2i = Vector2i.ZERO
		if fog_size_val is Vector2i:
			fog_size = fog_size_val
		elif typeof(fog_size_val) == TYPE_DICTIONARY:
			fog_size = Vector2i(fog_size_val.get("w", 0), fog_size_val.get("h", 0))
		save_game(maze.level, maze.run, player_pos, maze.rng_seed, fog_path, fog_size)

# Delete save on death (permadeath)
func _on_player_caught(_presence_cell: Vector2i, _player_cell: Vector2i) -> void:
	delete_save()
	print("[SaveManager] Run ended - save deleted")

# Save player stats on game won
func _on_game_won():
	save_player_stats(current_save_data.get("player_stats", {}))

func save_player_stats(stats: Dictionary) -> void:
	# Save player stats to the run-won file path for use on next runs
	var file := FileAccess.open(RUN_WON_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(stats)
		file.close()
		print("[SaveManager] Player stats saved to %s" % RUN_WON_FILE_PATH)
	else:
		push_error("[SaveManager] Failed to save player stats to %s" % RUN_WON_FILE_PATH)

func check_for_win() -> bool:
	# Check if the run-won file exists to determine if the player has won before
	return FileAccess.file_exists(RUN_WON_FILE_PATH)

func load_previous_win_stats() -> Dictionary:
	# Load player stats from the run-won file if it exists
	if check_for_win():
		var file := FileAccess.open(RUN_WON_FILE_PATH, FileAccess.READ)
		if file:
			var stats = file.get_var()
			file.close()
			print("[SaveManager] Loaded previous win stats: %s" % str(stats))
			return stats
		else:
			push_error("[SaveManager] Failed to load player stats from %s" % RUN_WON_FILE_PATH)
	return {}

