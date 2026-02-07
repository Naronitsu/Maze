extends Node
## Manages all UI updates via EventBus signals.
## Subscribes to game events and updates UI elements accordingly.

@onready var game: Node2D = get_parent() if get_parent() is Node2D else null

# UI element references (set when scene loads)
var level_intro_panel: CanvasItem
var level_intro_label: Label
var level_counter_label: Label
var game_over_panel: CanvasItem

var _intro_running: bool = false

func _ready() -> void:
	# Get UI element references
	level_intro_panel = game.get_node_or_null("UI/LevelIntro")
	if level_intro_panel:
		level_intro_label = level_intro_panel.get_node_or_null("Text")
	
	level_counter_label = game.get_node_or_null("UI/LevelCounter")
	game_over_panel = game.get_node_or_null("UI/GameOver")
	
	# Subscribe to EventBus signals
	EventBus.level_started.connect(_on_level_started)
	EventBus.level_transitioning.connect(_on_level_transitioning)
	EventBus.presence_caught_player.connect(_on_player_caught)
	EventBus.state_changed.connect(_on_state_changed)

func _on_level_started(_player_pos: Vector2i, maze: Node) -> void:
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

func _on_state_changed(from_state: String, to_state: String) -> void:
	print("[UIManager] State changed: %s -> %s" % [from_state, to_state])
	
	# Could add pause menu handling here
	# if to_state == "PAUSED":
	#     show_pause_menu()
	# elif from_state == "PAUSED":
	#     hide_pause_menu()

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
