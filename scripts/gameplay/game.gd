extends Node2D

# Use SceneReferences singleton instead of @onready decorators
var maze: DungeonMazeLayer
var presence: PresenceRW
var controller: GameController
var cam: Camera2D
var player: CharacterBody2D
var fog: FogOfWarRW
var transition_controller: TransitionController
var vision_controller: VisionController
var water_system: Node
var markings_spawner: Node

var _is_transitioning: bool = false
var _ready_complete: bool = false
var _is_continuing: bool = false
var _did_restore_fog: bool = false
var _continue_fog_path: String = ""
var _continue_fog_size: Vector2i = Vector2i.ZERO

const FOG_SAVE_PATH := "user://fog_explored.png"

func _ready() -> void:
	print("[Game] _ready() started")
	EventBus.pause_requested.connect(_on_pause_requested)
	EventBus.resume_requested.connect(_on_resume_requested)
	EventBus.return_to_menu_requested.connect(_return_to_main_menu)
	
	# Initialize scene references
	if not SceneReferences.validate_all(self):
		push_error("[Game] Failed to validate scene references")
		return
	
	# Cache references from SceneReferences
	maze = SceneReferences.maze
	presence = SceneReferences.presence
	controller = SceneReferences.controller
	cam = SceneReferences.camera
	player = SceneReferences.player
	fog = SceneReferences.fog
	water_system = SceneReferences.water_system

	# Decorative floor markings (non-colliding sprites)
	markings_spawner = preload("res://scripts/gameplay/markings_spawner.gd").new()
	add_child(markings_spawner)
	if markings_spawner.has_method("set_refs"):
		markings_spawner.call("set_refs", maze, controller)
	print("[Game._ready()] Water system ref: %s" % water_system)
	SettingsManager.apply_visuals_to_scene(self)
	
	# Create and initialize transition controller
	transition_controller = TransitionController.new()
	transition_controller.game = self
	transition_controller.maze = maze
	transition_controller.controller = controller
	transition_controller.presence = presence
	transition_controller.fog = fog
	transition_controller.ui_layer = SceneReferences.ui_layer
	transition_controller.level_intro_panel = SceneReferences.level_intro_panel
	transition_controller.level_intro_text = SceneReferences.level_intro_text
	add_child(transition_controller)
	
	# Wire fog to player for vision updates
	if fog and fog.has_method("set_player_and_presence"):
		fog.call("set_player_and_presence", player, presence)
	
	# Initialize vision controller
	vision_controller = VisionController.new()
	if vision_controller.initialize(player, cam, fog, presence):
		add_child(vision_controller)
		# Wire vision controller to player for facing updates
		player.vision_controller = vision_controller
		print("[Game] VisionController initialized")
	else:
		push_error("[Game] Failed to initialize VisionController")
	
	# Wire vision_controller and fog to heartbeat_ui if it exists
	var heartbeat_ui = get_node_or_null("HeartbeatUI")
	if heartbeat_ui != null:
		heartbeat_ui.vision_controller = vision_controller
		heartbeat_ui.fog = fog

	if water_system != null:
		water_system.set_refs(controller, player, presence)
	
	# Check if loading from save
	var save_data = SaveManager.current_save_data
	print("[Game] Save data: ", save_data)
	_is_continuing = save_data.has("level") and save_data.has("run")
	print("[Game] Is continuing: ", _is_continuing)
	
	if _is_continuing:
		# Load saved level/run/position/seed
		maze.level = save_data.get("level", 1)
		maze.run = save_data.get("run", 1)
		maze.rng_seed = save_data.get("maze_seed", 12345)
		var saved_cell: Vector2i = save_data.get("player_cell", Vector2i.ZERO)
		print("[Game] Loading saved game: Level %d, Run %d, Seed: %d, Position: %s" % [maze.level, maze.run, maze.rng_seed, saved_cell])
		_continue_fog_path = save_data.get("fog_path", "")
		_continue_fog_size = save_data.get("fog_size", Vector2i.ZERO)
	else:
		# New game - generate random seed
		maze.rng_seed = randi()
		print("[Game] New game with random seed: %d" % maze.rng_seed)
	
	# Generate + spawn first level
	print("[Game] Generating maze...")
	var maze_info = maze.generate()
	
	# Override spawn position if continuing from save
	if _is_continuing:
		var saved_cell: Vector2i = save_data.get("player_cell", Vector2i.ZERO)
		if saved_cell != Vector2i.ZERO:
			maze_info["spawn_override"] = saved_cell
	
	_start_new_level(maze_info)
	print("[Game] Waiting for maze setup...")
	await _after_maze_generated()
	print("[Game] Maze generated")

	# Wire refs for systems that expect them.
	if controller is GameController:
		(controller as GameController).player = player

	# Pause presence through intro + head start (no spawn yet)
	if presence != null:
		presence.set_process(false)

	# Skip intro if continuing from save
	if _is_continuing:
		print("[Game] Skipping intro for continue game")
		# Prevent SaveManager auto-save on initial level_started from overwriting
		# the just-loaded water/bucket state before we reapply it.
		SaveManager._auto_save_enabled = false
		GameState.current = GameState.State.PLAYING
		EventBus.level_started.emit(player.cell if "cell" in player else Vector2i.ZERO, maze)
		print("[Game] level_started signal emitted")
		call_deferred("_apply_continued_water_state", save_data)
		_ready_complete = true
		return

	# Show intro at game start (new game only) - use transition controller
	print("[Game] Showing intro sequence for new game")
	await _show_intro_sequence()
	
	# Set game state to playing after intro
	print("[Game] Intro complete, setting GameState to PLAYING")
	GameState.current = GameState.State.PLAYING
	
	# Emit level_started - PresenceSpawnManager will handle spawning
	EventBus.level_started.emit(player.cell if "cell" in player else Vector2i.ZERO, maze)
	print("[Game] level_started signal emitted")
	_ready_complete = true


func _apply_continued_water_state(save_data: Dictionary) -> void:
	# Reapply saved water/bucket state after the initial level_started resets.
	var ws := water_system
	if ws != null:
		# Prefer WaterSystem helper to also recreate/remove bucket visuals.
		if ws.has_method("apply_persistent_state"):
			var merged := save_data.duplicate(true)
			if not merged.has("bucket_cell"):
				merged["bucket_cell"] = save_data.get("player_cell", Vector2i.ZERO)
			ws.call("apply_persistent_state", merged)
		else:
			var amt: float = float(save_data.get("bucket_amount", GameConfig.water_bucket_start_amount))
			var placed: bool = bool(save_data.get("bucket_placed", false))
			var cell: Vector2i = save_data.get("bucket_cell", save_data.get("player_cell", Vector2i.ZERO))
			if "bucket_amount" in ws:
				ws.bucket_amount = clampf(amt, 0.0, GameConfig.water_bucket_capacity)
			if "bucket_placed" in ws:
				ws.bucket_placed = placed
			if "bucket_cell" in ws:
				ws.bucket_cell = cell
			if ws.has_method("_sync_bucket_node"):
				ws.call("_sync_bucket_node")
			elif ws.has_method("_remove_bucket_node") and not placed:
				ws.call("_remove_bucket_node")

	# Now that runtime state is correct, write it back once and re-enable autosave.
	var fog_path: String = save_data.get("fog_path", "")
	var fog_size: Vector2i = save_data.get("fog_size", Vector2i.ZERO)
	var ws_state: Dictionary = {}
	if ws != null and ws.has_method("get_persistent_state"):
		ws_state = ws.call("get_persistent_state")
	SaveManager.save_game(
		maze.level,
		maze.run,
		player.cell if "cell" in player else Vector2i.ZERO,
		maze.rng_seed,
		fog_path,
		fog_size,
		float(ws_state.get("bucket_amount", NAN)) if not ws_state.is_empty() else NAN,
		ws_state.get("bucket_placed", null) if not ws_state.is_empty() else null,
		ws_state.get("bucket_cell", SaveManager.INVALID_CELL) if not ws_state.is_empty() else SaveManager.INVALID_CELL
	)
	SaveManager._auto_save_enabled = true


func _input(event: InputEvent) -> void:
	# Toggle pause menu on ESC (but not during initialization)
	if not _ready_complete:
		return
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			set_paused_state(false)
		else:
			set_paused_state(true)

func _physics_process(_delta: float) -> void:
	if _is_transitioning:
		return
	if not ("cell" in player):
		return

	if (player.cell as Vector2i) == maze.exit_cell:
		print("[Game] Player reached exit at %s" % player.cell)
		# Require bucket to be placed before allowing level progression
		var ws := water_system
		# If a water system exists, require its `bucket_placed` flag to be true
		if ws != null:
			# Block progression when the bucket is placed in the world
			if ws.bucket_placed:
				print("[Game] Cannot progress: bucket is placed in the world")
				call_deferred("_display_temp_panel", "Pick up the bucket before progressing")
				return
		# Proceed with transition
		_is_transitioning = true
		GameState.current = GameState.State.TRANSITIONING
		EventBus.level_transitioning.emit()
		# Transition controller listens to this signal
		if transition_controller != null:
			transition_controller.start_transition()

# ========================================
# Intro Sequence
# ========================================

func _show_intro_sequence() -> void:
	"""Show intro text and fade out for new game"""
	if SceneReferences.level_intro_panel == null or SceneReferences.level_intro_text == null:
		return
	
	var panel = SceneReferences.level_intro_panel
	var label = SceneReferences.level_intro_text
	
	# Show text instantly
	panel.visible = true
	panel.modulate = Color(1, 1, 1, 1)
	label.visible = true
	label.text = GameConfig.door_message
	label.modulate = Color(1, 1, 1, 1)
	
	GameState.current = GameState.State.PAUSED
	
	# Hold text
	await get_tree().create_timer(GameConfig.door_text_hold_time).timeout
	
	# Fade out
	var t := create_tween()
	t.tween_property(label, "modulate:a", 0.0, GameConfig.door_fade_time)
	await t.finished
	
	var t2 := create_tween()
	t2.tween_property(panel, "modulate:a", 0.0, GameConfig.door_fade_time)
	await t2.finished
	
	panel.visible = false

func _display_temp_panel(msg: String, delay: float = 1.5, fade_time: float = 0.6) -> void:
	# Deferred async helper to show a one-off panel message then hide it
	if SceneReferences.level_intro_panel == null or SceneReferences.level_intro_text == null:
		return
	var panel := SceneReferences.level_intro_panel
	var label := SceneReferences.level_intro_text
	label.text = msg
	# Ensure both panel and label are visible and fully opaque
	panel.visible = true
	panel.modulate = Color(1, 1, 1, 1)
	label.visible = true
	label.modulate = Color(1, 1, 1, 1)
	# Wait, then fade both panel and label together
	await get_tree().create_timer(delay).timeout
	# If a transition started meanwhile, don't hide the intro panel (transition controller manages it)
	if _is_transitioning:
		return
	var t := create_tween()
	t.tween_property(panel, "modulate:a", 0.0, fade_time)
	t.tween_property(label, "modulate:a", 0.0, fade_time)
	await t.finished
	panel.visible = false
	label.visible = false

# ========================================
# Level / player setup
# ========================================
func _start_new_level(_info: Dictionary) -> void:
	# New maze means old history/trail are invalid.
	if controller is GameController:
		(controller as GameController).reset_for_new_level()
	
	# Use spawn override if provided (from save file)
	var spawn: Vector2i = _info.get("spawn_override", maze.get_spawn_cell())
	# Safety: if a saved cell is no longer valid (e.g. generator changed), don't spawn in a wall.
	spawn = _coerce_spawn_to_walkable(spawn)

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

	# Update camera limits for the newly generated maze.
	_update_camera_limits_for_current_maze()


func _coerce_spawn_to_walkable(desired: Vector2i) -> Vector2i:
	if maze == null:
		return desired
	if maze.is_floor(desired):
		return desired

	var fallback := maze.get_spawn_cell()
	if maze.is_floor(fallback):
		return fallback

	# Last resort: search a small radius for any walkable floor.
	var max_r := 10
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var c := Vector2i(desired.x + dx, desired.y + dy)
				if maze.is_floor(c):
					return c
	return desired

	# Fog should match new maze size and reset per level
	# But defer fog updates during transition to avoid visual flash
	if not _is_transitioning:
		if fog and fog.has_method("rebuild_for_current_maze"):
			fog.call_deferred("rebuild_for_current_maze")
		if fog and fog.has_method("reveal_now"):
			fog.call_deferred("reveal_now")

	_after_maze_generated()

func _after_maze_generated() -> void:
	_update_camera_limits_for_current_maze()
	
	if fog and fog.has_method("reset_fog_for_level"):
		fog.reset_fog_for_level()
		# Wait a frame for fog to settle
		await get_tree().process_frame

	if _is_continuing and (not _did_restore_fog) and _continue_fog_path != "":
		if fog and fog.has_method("load_explored_from_file"):
			fog.load_explored_from_file(_continue_fog_path, _continue_fog_size)
		# Only restore explored fog once on initial continue.
		_did_restore_fog = true

func _update_camera_limits_for_current_maze() -> void:
	if maze == null or cam == null:
		return
	var bounds: Rect2 = maze.get_world_bounds()
	cam.limit_left = int(floor(bounds.position.x))
	cam.limit_top = int(floor(bounds.position.y))
	cam.limit_right = int(ceil(bounds.position.x + bounds.size.x))
	cam.limit_bottom = int(ceil(bounds.position.y + bounds.size.y))
	# Avoid smoothing artifacts after teleports / limit changes.
	if cam.has_method("reset_smoothing"):
		cam.reset_smoothing()

func _return_to_main_menu() -> void:
	print("[Game] Returning to main menu")
	if get_tree().paused:
		get_tree().paused = false
	# Save current progress before leaving
	if maze and "level" in maze and "run" in maze:
		var fog_size := Vector2i.ZERO
		if fog and fog.has_method("save_explored_to_file"):
			fog_size = fog.save_explored_to_file(FOG_SAVE_PATH)
		SaveManager.save_game(
			maze.level,
			maze.run,
			player.cell if "cell" in player else Vector2i.ZERO,
			maze.rng_seed,
			FOG_SAVE_PATH if fog_size != Vector2i.ZERO else "",
			fog_size
		)
	
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func set_paused_state(is_paused: bool) -> void:
	if GameState.current == GameState.State.GAME_OVER:
		return
	if is_paused:
		if get_tree().paused:
			return
		get_tree().paused = true
		GameState.current = GameState.State.PAUSED
	else:
		if not get_tree().paused:
			return
		get_tree().paused = false
		GameState.current = GameState.State.PLAYING

func _on_pause_requested() -> void:
	set_paused_state(true)

func _on_resume_requested() -> void:
	set_paused_state(false)
