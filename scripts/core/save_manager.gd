extends Node
## SaveManager autoload - handles game save/load persistence.
## Saves current run state (level, run number, player position) to disk.

const SAVE_FILE_PATH = "user://save_data.json"
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
	"fog_size": Vector2i.ZERO,
	"bucket_amount": 0.0,
	"bucket_placed": false,
	"bucket_cell": Vector2i.ZERO,
	"water_cells": []
}

var _auto_save_enabled: bool = true

func _ready() -> void:
	add_to_group("persist")
	
	# Subscribe to game events for auto-save
	EventBus.level_started.connect(_on_level_started)
	EventBus.presence_caught_player.connect(_on_player_caught)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_FILE_PATH)

func save_game(
	level: int,
	run: int,
	player_cell: Vector2i = Vector2i.ZERO,
	maze_seed: int = 0,
	fog_path: String = "",
	fog_size: Vector2i = Vector2i.ZERO,
	bucket_amount: float = NAN,
	bucket_placed: Variant = null,
	bucket_cell: Vector2i = INVALID_CELL
) -> bool:
	var fog_size_dict := {"w": fog_size.x, "h": fog_size.y}

	var ws_state: Dictionary = {}
	if SceneReferences.water_system != null and SceneReferences.water_system.has_method("get_persistent_state"):
		ws_state = SceneReferences.water_system.call("get_persistent_state")

	var bucket_amount_to_save := bucket_amount
	if is_nan(bucket_amount_to_save):
		if not ws_state.is_empty() and ws_state.has("bucket_amount"):
			bucket_amount_to_save = float(ws_state.get("bucket_amount"))
		else:
			bucket_amount_to_save = clampf(GameConfig.water_bucket_start_amount, 0.0, GameConfig.water_bucket_capacity)
	bucket_amount_to_save = clampf(bucket_amount_to_save, 0.0, GameConfig.water_bucket_capacity)

	var bucket_placed_to_save := false
	if bucket_placed != null and typeof(bucket_placed) == TYPE_BOOL:
		bucket_placed_to_save = bool(bucket_placed)
	elif not ws_state.is_empty() and ws_state.has("bucket_placed"):
		bucket_placed_to_save = bool(ws_state.get("bucket_placed"))

	var bucket_cell_to_save := bucket_cell
	if bucket_cell_to_save == INVALID_CELL:
		if not ws_state.is_empty() and ws_state.has("bucket_cell"):
			bucket_cell_to_save = ws_state.get("bucket_cell")
		else:
			bucket_cell_to_save = player_cell

	var bucket_cell_dict := {"x": bucket_cell_to_save.x, "y": bucket_cell_to_save.y}
	var water_cells_to_save: Array = []
	if not ws_state.is_empty() and ws_state.has("water_cells") and typeof(ws_state.get("water_cells")) == TYPE_ARRAY:
		water_cells_to_save = ws_state.get("water_cells")
	var save_dict = {
		"level": level,
		"run": run,
		"player_cell": {"x": player_cell.x, "y": player_cell.y},
		"maze_seed": maze_seed,
		"timestamp": Time.get_unix_time_from_system(),
		"fog_path": fog_path,
		"fog_size": fog_size_dict,
		"bucket_amount": bucket_amount_to_save,
		"bucket_placed": bucket_placed_to_save,
		"bucket_cell": bucket_cell_dict,
		"water_cells": water_cells_to_save
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
	current_save_data.bucket_amount = bucket_amount_to_save
	current_save_data.bucket_placed = bucket_placed_to_save
	current_save_data.bucket_cell = bucket_cell_to_save
	current_save_data.water_cells = water_cells_to_save
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

	# Convert bucket_cell dict back to Vector2i
	if data.has("bucket_cell") and typeof(data.bucket_cell) == TYPE_DICTIONARY:
		var bc = data.bucket_cell
		data.bucket_cell = Vector2i(bc.get("x", 0), bc.get("y", 0))
	else:
		data.bucket_cell = Vector2i.ZERO

	# Water (backward-compatible)
	var default_bucket := clampf(GameConfig.water_bucket_start_amount, 0.0, GameConfig.water_bucket_capacity)
	var raw_bucket: Variant = data.get("bucket_amount", default_bucket)
	if typeof(raw_bucket) == TYPE_INT or typeof(raw_bucket) == TYPE_FLOAT:
		data.bucket_amount = clampf(float(raw_bucket), 0.0, GameConfig.water_bucket_capacity)
	else:
		data.bucket_amount = default_bucket
	data.bucket_placed = bool(data.get("bucket_placed", false))
	# Droplet puddles
	var wc: Variant = data.get("water_cells", [])
	if typeof(wc) != TYPE_ARRAY:
		data.water_cells = []
	else:
		data.water_cells = wc
	
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
		"fog_size": Vector2i.ZERO,
		"bucket_amount": clampf(GameConfig.water_bucket_start_amount, 0.0, GameConfig.water_bucket_capacity),
		"bucket_placed": false,
		"bucket_cell": Vector2i.ZERO,
		"water_cells": []
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
