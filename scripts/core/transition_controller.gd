extends Node
class_name TransitionController
## Centralized level transition orchestration
## Manages the entire sequence: pause → fade in → generate → fade out

enum Phase {
	IDLE,
	DOOR_PAUSE,
	FADE_IN,
	TEXT_HOLD,
	GENERATING,
	FADE_OUT,
	SETTLING,
	COMPLETE
}

var _current_phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0

# References (set by caller)
var game: Node2D
var maze: DungeonMazeLayer
var controller: GameController
var presence: PresenceRW
var fog: FogOfWarRW
var ui_layer: CanvasLayer
var level_intro_panel: ColorRect
var level_intro_text: Label

func _process(delta: float) -> void:
	if _current_phase == Phase.IDLE:
		return
	
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_advance_phase()

## Start a level transition
func start_transition() -> void:
	if _current_phase != Phase.IDLE:
		return
	
	print("[TransitionController] Starting transition sequence")
	
	# Freeze player and presence
	if game.player != null and game.player.has_method("reset_to_cell"):
		game.player.reset_to_cell(game.player.cell)
	
	if presence != null:
		presence.set_process(false)
	
	# Show black panel IMMEDIATELY to prevent any flash
	if level_intro_panel != null:
		level_intro_panel.z_index = 100
		level_intro_panel.visible = true
		level_intro_panel.modulate = Color(1, 1, 1, 1)
		if level_intro_text != null:
			level_intro_text.modulate = Color(1, 1, 1, 0)
	
	# Start transition sequence
	_current_phase = Phase.DOOR_PAUSE
	_phase_timer = GameConfig.door_pause_time
	print("[TransitionController] Phase: DOOR_PAUSE")

func _advance_phase() -> void:
	match _current_phase:
		Phase.DOOR_PAUSE:
			_current_phase = Phase.FADE_IN
			_fade_in_text(GameConfig.door_message, GameConfig.door_fade_time)
			_phase_timer = GameConfig.door_fade_time
			print("[TransitionController] Phase: FADE_IN")
		
		Phase.FADE_IN:
			_current_phase = Phase.TEXT_HOLD
			_phase_timer = GameConfig.door_text_hold_time
			print("[TransitionController] Phase: TEXT_HOLD")
		
		Phase.TEXT_HOLD:
			_current_phase = Phase.GENERATING
			_generate_new_level()
			_phase_timer = 0.1
			print("[TransitionController] Phase: GENERATING")
		
		Phase.GENERATING:
			_current_phase = Phase.FADE_OUT
			_fade_out_text(GameConfig.door_fade_time)
			_phase_timer = GameConfig.door_fade_time * 2  # Account for text + panel fade
			print("[TransitionController] Phase: FADE_OUT")
		
		Phase.FADE_OUT:
			_current_phase = Phase.SETTLING
			_phase_timer = 0.05
			print("[TransitionController] Phase: SETTLING")
		
		Phase.SETTLING:
			_current_phase = Phase.COMPLETE
			_complete_transition()
			print("[TransitionController] Phase: COMPLETE")

func _fade_in_text(msg: String, fade_time: float) -> void:
	if level_intro_text == null:
		return
	
	level_intro_text.text = msg
	level_intro_text.visible = true
	level_intro_text.modulate = Color(1, 1, 1, 0)
	
	GameState.current = GameState.State.PAUSED
	
	# Wait one frame for UI to settle
	await get_tree().process_frame
	
	var t := create_tween()
	t.tween_property(level_intro_text, "modulate:a", 1.0, fade_time)
	await t.finished

func _fade_out_text(fade_time: float) -> void:
	if level_intro_text == null or level_intro_panel == null:
		return
	
	# Fade out the text first
	var t := create_tween()
	t.tween_property(level_intro_text, "modulate:a", 0.0, fade_time)
	await t.finished
	
	# Then fade out the black panel
	var t2 := create_tween()
	t2.tween_property(level_intro_panel, "modulate:a", 0.0, fade_time)
	await t2.finished
	
	level_intro_panel.visible = false

func _generate_new_level() -> void:
	if maze == null or controller == null:
		return
	
	# Advance difficulty
	if maze.level >= GameConfig.max_levels_before_reset:
		maze.advance_run()
	else:
		maze.level += 1
	
	# Generate new maze
	var info: Dictionary = maze.generate()
	game._start_new_level(info)

func _complete_transition() -> void:
	print("[TransitionController] Setting GameState to PLAYING")
	game._is_transitioning = false
	
	# Rebuild fog after transition is complete
	if fog != null and fog.has_method("rebuild_for_current_maze"):
		fog.rebuild_for_current_maze()
	if fog != null and fog.has_method("reveal_now"):
		fog.reveal_now()
	
	GameState.current = GameState.State.PLAYING
	
	# Emit level_started for other systems
	EventBus.level_started.emit(
		game.player.cell if "cell" in game.player else Vector2i.ZERO,
		maze
	)
	
	# Reset to idle
	_current_phase = Phase.IDLE
	print("[TransitionController] Transition complete")
