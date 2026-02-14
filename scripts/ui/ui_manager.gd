extends Node
## Manages all UI updates via EventBus signals.
## Subscribes to game events and updates UI elements accordingly.

@onready var game: Node2D = get_parent() if get_parent() is Node2D else null

# UI element references (set when scene loads)
var level_intro_panel: CanvasItem
var level_intro_label: Label
var level_counter_label: Label
var game_over_panel: CanvasItem
var pause_menu: Control
var pause_settings: Control

var _crt_overlay: ColorRect
var _crt_saved_curvature: float = 0.0
var _crt_has_saved_curvature: bool = false

var _intro_running: bool = false
var _is_loading_scene: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Get UI element references
	level_intro_panel = game.get_node_or_null("UI/LevelIntro")
	if level_intro_panel:
		level_intro_label = level_intro_panel.get_node_or_null("Text")
	
	level_counter_label = game.get_node_or_null("UI/LevelCounter")
	game_over_panel = game.get_node_or_null("UI/GameOver")
	pause_menu = game.get_node_or_null("UI/PauseMenu")
	pause_settings = game.get_node_or_null("UI/PauseSettings")
	_crt_overlay = game.get_node_or_null("CRT/CRTOverlay") as ColorRect
	_cache_crt_curvature()

	if pause_menu:
		pause_menu.connect("resume_pressed", _on_pause_resume)
		pause_menu.connect("settings_pressed", _on_pause_settings)
		pause_menu.connect("quit_pressed", _on_pause_quit)

	if pause_settings:
		pause_settings.connect("back_pressed", _on_settings_back)
	
	# Subscribe to EventBus signals
	EventBus.level_started.connect(_on_level_started)
	EventBus.level_transitioning.connect(_on_level_transitioning)
	EventBus.presence_caught_player.connect(_on_player_caught)
	EventBus.game_over.connect(_on_game_over)
	EventBus.state_changed.connect(_on_state_changed)

	# Listen for loading events from SceneLoader
	if SceneLoader.has_signal("scene_loading_started"):
		SceneLoader.scene_loading_started.connect(_on_scene_loading_started)
	if SceneLoader.has_signal("scene_loading_finished"):
		SceneLoader.scene_loading_finished.connect(_on_scene_loading_finished)

	_hide_pause_menu()
	_hide_settings_menu()


func _on_scene_loading_started():
	_is_loading_scene = true
	_hide_pause_menu()

func _on_scene_loading_finished():
	_is_loading_scene = false

func _on_level_started(_player_pos: Vector2i, maze: Node) -> void:

	if SceneLoader.has_signal("scene_loading_finished") and SceneLoader.is_loading:
		await SceneLoader.scene_loading_finished
		await RenderingServer.frame_post_draw

	# Update level counter
	if level_counter_label and maze and "level" in maze:
		level_counter_label.text = "Level %d" % maze.level
	
	# Hide intro panel when level starts
	if level_intro_panel:
		await get_tree().create_timer(0.5).timeout  # Brief delay
		_fade_out_intro()

func _on_level_transitioning() -> void:
	# Show transition message
	_show_intro_instant(GameConfig.door_message)

func _on_player_caught(_presence_cell: Vector2i, _player_cell: Vector2i) -> void:
	# Show game over screen
	if game_over_panel:
		game_over_panel.visible = true
		game_over_panel.modulate.a = 0.0
		
		var t := get_tree().create_tween()
		t.tween_property(game_over_panel, "modulate:a", 1.0, 0.5)

func _on_game_over() -> void:
	if game_over_panel:
		game_over_panel.visible = true
		game_over_panel.modulate.a = 0.0
		var t := get_tree().create_tween()
		t.tween_property(game_over_panel, "modulate:a", 1.0, 0.5)

func _on_state_changed(from_state: String, to_state: String) -> void:
	print("[UIManager] State changed: %s -> %s" % [from_state, to_state])
	if to_state == "PAUSED" and get_tree().paused and not SceneLoader.is_loading:
		_set_ui_mouse_mode(true)
		_show_pause_menu()
	elif from_state == "PAUSED":
		_hide_pause_menu()
		_hide_settings_menu()
		_set_ui_mouse_mode(false)

func _on_pause_resume() -> void:
	EventBus.resume_requested.emit()

func _on_pause_settings() -> void:
	_show_settings_menu()

func _on_pause_quit() -> void:
	EventBus.return_to_menu_requested.emit()

func _on_settings_back() -> void:
	_show_pause_menu()

func _show_pause_menu() -> void:
	_set_ui_mouse_mode(true)
	if pause_settings:
		pause_settings.visible = false
	if pause_menu:
		pause_menu.visible = true

func _hide_pause_menu() -> void:
	if pause_menu:
		pause_menu.visible = false

func _show_settings_menu() -> void:
	_set_ui_mouse_mode(true)
	if pause_menu:
		pause_menu.visible = false
	if pause_settings:
		pause_settings.visible = true

func _hide_settings_menu() -> void:
	if pause_settings:
		pause_settings.visible = false

func _cache_crt_curvature() -> void:
	if _crt_overlay == null:
		return
	if not (_crt_overlay.material is ShaderMaterial):
		return
	var mat := _crt_overlay.material as ShaderMaterial
	if mat == null:
		return
	var v: Variant = mat.get_shader_parameter("curvature")
	if v is float:
		_crt_saved_curvature = float(v)
		_crt_has_saved_curvature = true

func _set_ui_mouse_mode(active: bool) -> void:
	# CRT warp is a post-process visual distortion; it does not warp input hitboxes.
	# While menus are open (mouse-driven), disable curvature so clicks align.
	if _crt_overlay == null or not (_crt_overlay.material is ShaderMaterial):
		return
	var mat := _crt_overlay.material as ShaderMaterial
	if mat == null:
		return
	if active:
		if not _crt_has_saved_curvature:
			_cache_crt_curvature()
		mat.set_shader_parameter("curvature", 0.0)
	else:
		if _crt_has_saved_curvature:
			mat.set_shader_parameter("curvature", _crt_saved_curvature)

# ------------------------
# Intro screen methods
# ------------------------
func _show_intro_instant(msg: String) -> void:
	if _intro_running or not level_intro_panel:
		return
	_intro_running = true
	
	if level_intro_label:
		level_intro_label.text = msg
	
	level_intro_panel.visible = true
	level_intro_panel.modulate.a = 1.0

func _fade_in_intro(msg: String, fade_time: float) -> void:
	if _intro_running or not level_intro_panel:
		return
	_intro_running = true
	
	if level_intro_label:
		level_intro_label.text = msg
	
	level_intro_panel.visible = true
	level_intro_panel.modulate.a = 0.0
	
	var t := get_tree().create_tween()
	t.tween_property(level_intro_panel, "modulate:a", 1.0, fade_time)
	await t.finished

func _fade_out_intro() -> void:
	if not level_intro_panel or not _intro_running:
		return
	
	var fade_time = GameConfig.door_fade_time
	var t := get_tree().create_tween()
	t.tween_property(level_intro_panel, "modulate:a", 0.0, fade_time)
	await t.finished
	
	level_intro_panel.visible = false
	_intro_running = false
