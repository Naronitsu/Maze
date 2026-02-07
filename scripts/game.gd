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

var _is_transitioning: bool = false
var _ready_complete: bool = false

func _ready() -> void:
	print("[Game] _ready() started")
	
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
	
	# Check if loading from save
	var save_data = SaveManager.current_save_data
	print("[Game] Save data: ", save_data)
	var is_continuing = save_data.has("level") and save_data.has("run")
	print("[Game] Is continuing: ", is_continuing)
	
	if is_continuing:
		# Load saved level/run/position/seed
		maze.level = save_data.get("level", 1)
		maze.run = save_data.get("run", 1)
		maze.rng_seed = save_data.get("maze_seed", 12345)
		var saved_cell: Vector2i = save_data.get("player_cell", Vector2i.ZERO)
		print("[Game] Loading saved game: Level %d, Run %d, Seed: %d, Position: %s" % [maze.level, maze.run, maze.rng_seed, saved_cell])
	else:
		# New game - generate random seed
		maze.rng_seed = randi()
		print("[Game] New game with random seed: %d" % maze.rng_seed)
	
	# Generate + spawn first level
	print("[Game] Generating maze...")
	var maze_info = maze.generate()
	
	# Override spawn position if continuing from save
	if is_continuing:
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
	if is_continuing:
		print("[Game] Skipping intro for continue game")
		GameState.current = GameState.State.PLAYING
		EventBus.level_started.emit(player.cell if "cell" in player else Vector2i.ZERO, maze)
		print("[Game] level_started signal emitted")
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

func _input(event: InputEvent) -> void:
	# Return to main menu on ESC (but not during initialization)
	if not _ready_complete:
		return
	if event.is_action_pressed("ui_cancel"):
		_return_to_main_menu()

func _physics_process(_delta: float) -> void:
	if _is_transitioning:
		return
	if not ("cell" in player):
		return

	if (player.cell as Vector2i) == maze.exit_cell:
		print("[Game] Player reached exit at %s" % player.cell)
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

# ========================================
# Level / player setup
# ========================================
func _start_new_level(_info: Dictionary) -> void:
	# New maze means old history/trail are invalid.
	if controller is GameController:
		(controller as GameController).reset_for_new_level()
	
	# Use spawn override if provided (from save file)
	var spawn: Vector2i = _info.get("spawn_override", maze.get_spawn_cell())

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
	# But defer fog updates during transition to avoid visual flash
	if not _is_transitioning:
		if fog and fog.has_method("rebuild_for_current_maze"):
			fog.call_deferred("rebuild_for_current_maze")
		if fog and fog.has_method("reveal_now"):
			fog.call_deferred("reveal_now")

	_after_maze_generated()

func _after_maze_generated() -> void:
	var bounds: Rect2 = maze.get_world_bounds()

	cam.limit_left   = int(floor(bounds.position.x))
	cam.limit_top    = int(floor(bounds.position.y))
	cam.limit_right  = int(ceil(bounds.position.x + bounds.size.x))
	cam.limit_bottom = int(ceil(bounds.position.y + bounds.size.y))
	
	if fog and fog.has_method("reset_fog_for_level"):
		fog.reset_fog_for_level()
		# Wait a frame for fog to settle
		await get_tree().process_frame

func _return_to_main_menu() -> void:
	print("[Game] Returning to main menu")
	# Save current progress before leaving
	if maze and "level" in maze and "run" in maze:
		SaveManager.save_game(maze.level, maze.run, player.cell if "cell" in player else Vector2i.ZERO, maze.rng_seed)
	
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func set_player_input_enabled(v: bool) -> void:
	if player != null:
		player.set_physics_process(v)
