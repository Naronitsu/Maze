extends Node2D

@export var max_levels_before_reset: int = 10

# Door transition tuning
@export var door_pause_time: float = 0.25
@export var door_fade_time: float = 0.20
@export var door_text_hold_time: float = 0.8
@export var door_message_time: float = 1.2
@export var door_message: String = "there is a monster behind you, run"

# Presence pacing / spawning
@export var presence_head_start_time: float = 2.5
@export var presence_min_spawn_dist_cells: int = 12
@export var presence_min_history_steps: int = 8
@export var presence_wait_history_max_seconds: float = 6.0

@onready var maze: DungeonMazeLayer = $TileMap/MazeLayer
@onready var presence: PresenceRW = $PresenceRW
@onready var controller: Node = $GameController
@onready var cam: Camera2D = $Player/Camera
@onready var player: CharacterBody2D = $Player

@onready var fog: FogOfWarRW = $Overlay/FogOfWarRW

var _transitioning: bool = false
var _intro_running: bool = false

func _ready() -> void:
	# Generate + spawn first level
	_start_new_level(maze.generate())
	_after_maze_generated()

	# Wire refs for systems that expect them.
	if controller is GameController:
		(controller as GameController).player = player

	# Pause presence through intro + head start (no spawn yet)
	if presence != null:
		presence.set_process(false)

	# Show intro at game start
	_level_intro_show_instant(door_message)
	await get_tree().create_timer(door_text_hold_time).timeout
	await _level_intro_fade_out(door_fade_time)

	# Head start time
	await get_tree().create_timer(presence_head_start_time).timeout

	# Also wait until history exists (player actually moved)
	await _wait_for_player_history(presence_min_history_steps, presence_wait_history_max_seconds)

	# Spawn monster behind if possible, else fallback far
	_spawn_presence_behind_or_fallback()

func _physics_process(_delta: float) -> void:
	if _transitioning:
		return
	if not ("cell" in player):
		return

	if (player.cell as Vector2i) == maze.exit_cell:
		_transitioning = true
		call_deferred("_door_transition_and_advance")

func _door_transition_and_advance() -> void:
	# Freeze player in place (prevents extra input during transition)
	if player != null and player.has_method("reset_to_cell") and ("cell" in player):
		player.reset_to_cell(player.cell)

	# Pause PresenceRW during transition
	if presence != null:
		presence.set_process(false)

	await get_tree().create_timer(door_pause_time).timeout

	await _level_intro_fade_in(door_message, door_fade_time)
	await get_tree().create_timer(door_text_hold_time).timeout

	# Advance difficulty
	if maze.level >= max_levels_before_reset:
		maze.advance_run()
	else:
		maze.advance_level()

	# ✅ ACTUALLY REGENERATE THE MAZE
	var info: Dictionary = maze.generate()
	_start_new_level(info)

	await get_tree().process_frame
	await _level_intro_fade_out(door_fade_time)

	# Wait one frame for player/fog/camera to settle and for history to contain new-cell entries
	await get_tree().process_frame

	# Head start again on every new level
	await get_tree().create_timer(presence_head_start_time).timeout

	# Wait until we actually have enough breadcrumbs
	await _wait_for_player_history(
		presence_min_spawn_dist_cells + 1,
		presence_wait_history_max_seconds
	)

	_spawn_presence_behind_or_fallback()
	_transitioning = false

# -----------------------------
# Presence spawn helpers
# -----------------------------
func _wait_for_player_history(min_len: int, max_seconds: float) -> void:
	if controller == null:
		return
	var waited := 0.0
	while waited < max_seconds:
		var hist_v: Variant = controller.get("player_history")
		if typeof(hist_v) == TYPE_ARRAY and (hist_v as Array).size() >= min_len:
			return
		await get_tree().process_frame
		waited += get_process_delta_time()

func _spawn_presence_behind_or_fallback() -> void:
	if presence == null or controller == null:
		return

	presence.set_process(false)

	# Wait until we have enough history OR we hit the timeout
	await _wait_for_player_history(presence_min_spawn_dist_cells + 1, presence_wait_history_max_seconds)

	var ok := false
	if presence.has_method("respawn_from_history"):
		ok = presence.respawn_from_history()

	# New behind-biased fallback (room start / early history)
	if not ok and presence.has_method("respawn_from_room_start"):
		ok = presence.respawn_from_room_start()

	# Absolute fallback
	if not ok and presence.has_method("respawn_far_from_player"):
		presence.respawn_far_from_player(presence_min_spawn_dist_cells)
		ok = true

	# If you hide it anywhere, make sure it’s visible
	presence.visible = true
	presence.set_process(ok)

# -----------------------------
# Level / player setup
# -----------------------------
func _start_new_level(_info: Dictionary) -> void:
	# New maze means old history/trail are invalid.
	if controller is GameController:
		(controller as GameController).reset_for_new_level()
	var spawn: Vector2i = maze.get_spawn_cell()

	# Keep player script synced
	if "maze_path" in player:
		player.maze_path = maze.get_path()

	if player.has_method("reset_to_cell"):
		player.reset_to_cell(spawn)
	else:
		player.global_position = maze.cell_to_global(spawn)
		if "cell" in player:
			player.cell = spawn

	if controller is GameController:
		var gc := controller as GameController
		gc.player = player
		gc.presence = presence
		gc.record_player_cell(spawn)

	# Fog should match new maze size and reset per level
	if fog and fog.has_method("rebuild_for_current_maze"):
		fog.call_deferred("rebuild_for_current_maze")
	if fog and fog.has_method("reveal_now"):
		fog.call_deferred("reveal_now")

	_after_maze_generated()

func play_presence_sound(pos: Vector2) -> void:
	var a: AudioStreamPlayer2D = $SubViewport/PresenceAudio
	a.global_position = pos
	a.pitch_scale = randf_range(0.92, 1.08)
	a.stop()
	a.play()

var _is_flickering: bool = false

func presence_flicker() -> void:
	if _is_flickering:
		return
	if not has_node("CanvasModulate"):
		return

	_is_flickering = true

	var cm: CanvasModulate = $SubViewport/CanvasModulate
	var old: Color = cm.color
	var blackout: Color = Color(old.r * 0.05, old.g * 0.05, old.b * 0.05, 1.0)

	cm.color = blackout
	await get_tree().create_timer(0.45).timeout

	cm.color = old
	_is_flickering = false

var _blackout_running: bool = false

func presence_blackout(duration: float = 0.45, fade: float = 0.08) -> void:
	if _blackout_running:
		return
	_blackout_running = true
	if not has_node("Overlay/Blackout"):
		_blackout_running = false
		return

	var rect: ColorRect = $SubViewport/Overlay/Blackout
	rect.visible = true
	rect.modulate.a = 0.0

	var t := create_tween()
	t.tween_property(rect, "modulate:a", 1.0, fade)
	t.tween_interval(max(0.0, duration))
	t.tween_property(rect, "modulate:a", 0.0, fade)
	await t.finished

	rect.visible = false
	_blackout_running = false

func _after_maze_generated() -> void:
	var bounds: Rect2 = maze.get_world_bounds()

	cam.limit_left   = int(floor(bounds.position.x))
	cam.limit_top    = int(floor(bounds.position.y))
	cam.limit_right  = int(ceil(bounds.position.x + bounds.size.x))
	cam.limit_bottom = int(ceil(bounds.position.y + bounds.size.y))
	
	await fog.reset_fog_for_level()

func _level_intro_fade_in(msg: String, fade_time: float) -> void:
	if _intro_running:
		return
	_intro_running = true

	var panel: CanvasItem = $UI/LevelIntro
	var label: Label = $UI/LevelIntro/Text

	label.text = msg
	panel.visible = true
	panel.modulate.a = 0.0

	if has_method("set_player_input_enabled"):
		call("set_player_input_enabled", false)

	var t := create_tween()
	t.tween_property(panel, "modulate:a", 1.0, fade_time)
	await t.finished

func _level_intro_fade_out(fade_time: float) -> void:
	var panel: CanvasItem = $UI/LevelIntro
	if panel == null:
		_intro_running = false
		return

	var t := create_tween()
	t.tween_property(panel, "modulate:a", 0.0, fade_time)
	await t.finished

	panel.visible = false

	if has_method("set_player_input_enabled"):
		call("set_player_input_enabled", true)

	_intro_running = false

func set_player_input_enabled(v: bool) -> void:
	if player != null:
		player.set_physics_process(v)

func _level_intro_show_instant(msg: String) -> void:
	if _intro_running:
		return
	_intro_running = true

	var panel: CanvasItem = $UI/LevelIntro
	var label: Label = $UI/LevelIntro/Text

	label.text = msg
	panel.visible = true
	panel.modulate.a = 1.0

	if has_method("set_player_input_enabled"):
		call("set_player_input_enabled", false)
