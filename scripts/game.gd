extends Node2D

@export var max_levels_before_reset: int = 10

@onready var maze: MazeLayer = $TileMap/MazeLayer
@onready var player: CharacterBody2D = $Player
@onready var presence: Node = $Presence
@onready var cam: Camera2D = $Player/Camera

@onready var fog := $FogOfWar

var _transitioning: bool = false

func _ready() -> void:
	_start_new_level(maze.generate())
	_clamp_camera_to_maze()
	presence.setup(player,maze)


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
	await show_level_intro()
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

	# tiny variation so it feels alive
	a.pitch_scale = randf_range(0.92, 1.08)

	# restart cleanly even if it was already playing
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

	# Fade to near-black
	var blackout: Color = Color(
		old.r * 0.05,
		old.g * 0.05,
		old.b * 0.05,
		1.0
	)

	cm.color = blackout
	await get_tree().create_timer(0.45).timeout

	# Come back abruptly (scarier than a smooth fade)
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

	cam.limit_left   = int(bounds.position.x)
	cam.limit_top    = int(bounds.position.y)
	cam.limit_right  = int(bounds.position.x + bounds.size.x)
	cam.limit_bottom = int(bounds.position.y + bounds.size.y)

var _intro_running: bool = false

func show_level_intro(msg: String = "there is a monster behind you, run", duration: float = 1.6) -> void:
	if _intro_running:
		return
	_intro_running = true

	var panel: CanvasItem = $UI/LevelIntro
	var label: Label = $UI/LevelIntro/Text

	label.text = msg
	panel.visible = true

	# Optional: freeze player input while intro is up
	if has_method("set_player_input_enabled"):
		call("set_player_input_enabled", false)

	await get_tree().create_timer(duration).timeout

	panel.visible = false

	if has_method("set_player_input_enabled"):
		call("set_player_input_enabled", true)

	_intro_running = false
	
func _clamp_camera_to_maze() -> void:
	var bounds: Rect2 = maze.get_world_bounds()

	cam.limit_left   = int(bounds.position.x)
	cam.limit_top    = int(bounds.position.y)
	cam.limit_right  = int(bounds.position.x + bounds.size.x)
	cam.limit_bottom = int(bounds.position.y + bounds.size.y)
