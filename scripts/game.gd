extends Node2D

@export var max_levels_before_reset: int = 10

# Door transition tuning
@export var door_pause_time: float = 0.25
@export var door_fade_time: float = 0.20
@export var door_message_time: float = 1.2
@export var door_message: String = "there is a monster behind you, run"

@onready var maze: MazeLayer = $TileMap/MazeLayer
@onready var player: CharacterBody2D = $Player
@onready var presence: Node = $Presence
@onready var cam: Camera2D = $Player/Camera
@onready var fog := $FogOfWar

var _transitioning: bool = false
var _intro_running: bool = false

func _ready() -> void:
	_start_new_level(maze.generate())
	_after_maze_generated()
	presence.setup(player, maze)

func _physics_process(_delta: float) -> void:
	if _transitioning:
		return

	# Only works if player has `cell: Vector2i`
	if not ("cell" in player):
		return

	# Exit only (entrance door does nothing)
	if (player.cell as Vector2i) == maze.exit_cell:
		_transitioning = true
		call_deferred("_door_transition_and_advance")

func _door_transition_and_advance() -> void:
	# Freeze player in place (prevents extra input during transition)
	if player != null and player.has_method("reset_to_cell") and ("cell" in player):
		player.reset_to_cell(player.cell)

	# Pause Presence events during transition
	if presence != null:
		presence.set_process(false)

	# Small dramatic pause at the door
	await get_tree().create_timer(door_pause_time).timeout

	# Fade in message, hold, fade out
	await _show_level_intro_fade(door_message, door_message_time, door_fade_time)

	# Advance maze
	var info: Dictionary
	if maze.level >= max_levels_before_reset:
		info = maze.advance_run()
	else:
		info = maze.advance_level()

	await _start_new_level(info)

	# Resume Presence
	if presence != null:
		presence.set_process(true)

	_transitioning = false

func _start_new_level(_info: Dictionary) -> void:
	var spawn: Vector2i = maze.get_spawn_cell()

	# If your player script uses a TileMap reference, keep it synced
	if "maze_path" in player:
		player.maze_path = maze.get_path()

	# Prefer calling player's reset method (cancels in-progress movement)
	if player.has_method("reset_to_cell"):
		player.reset_to_cell(spawn)
	else:
		player.global_position = maze.cell_to_global(spawn)
		if "cell" in player:
			player.cell = spawn

	# Fog should match new maze size and reset per level
	if fog and fog.has_method("rebuild_for_current_maze"):
		fog.call_deferred("rebuild_for_current_maze")
	if fog and fog.has_method("reveal_now"):
		fog.call_deferred("reveal_now")

	_after_maze_generated()

func play_presence_sound(pos: Vector2) -> void:
	var a: AudioStreamPlayer2D = $PresenceAudio
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

	var cm: CanvasModulate = $CanvasModulate
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

	var rect: ColorRect = $Overlay/Blackout
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

func _show_level_intro_fade(msg: String, hold_time: float, fade_time: float) -> void:
	if _intro_running:
		return
	_intro_running = true

	var panel: CanvasItem = $UI/LevelIntro
	var label: Label = $UI/LevelIntro/Text

	label.text = msg
	panel.visible = true
	panel.modulate.a = 0.0

	# Optional: freeze player input while intro is up
	if has_method("set_player_input_enabled"):
		call("set_player_input_enabled", false)

	# Fade in
	var t := create_tween()
	t.tween_property(panel, "modulate:a", 1.0, fade_time)
	await t.finished

	# Hold
	await get_tree().create_timer(max(0.0, hold_time)).timeout

	# Fade out
	t = create_tween()
	t.tween_property(panel, "modulate:a", 0.0, fade_time)
	await t.finished

	panel.visible = false

	if has_method("set_player_input_enabled"):
		call("set_player_input_enabled", true)

	_intro_running = false
