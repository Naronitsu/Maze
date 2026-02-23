extends Node
class_name TransitionController
## Centralized level transition orchestration
## Sequence: pause → level up (pick) → fade in text → hold → generate → fade out → resume

enum Phase {
	IDLE,
	DOOR_PAUSE,
	LEVEL_UP,
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
var level_up_panel: LevelUpPanel

func _process(delta: float) -> void:
	if _current_phase == Phase.IDLE:
		return

	# HARD STOP: wait here until player picks an upgrade
	if _current_phase == Phase.LEVEL_UP:
		return

	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_advance_phase()

## Start a level transition
func start_transition() -> void:
	if _current_phase != Phase.IDLE:
		return

	print("[TransitionController] Starting transition sequence")

	# Pause immediately so nothing can start early
	GameState.current = GameState.State.PAUSED

	# Freeze player and presence
	if game != null and game.player != null and game.player.has_method("reset_to_cell"):
		game.player.reset_to_cell(game.player.cell)

	if presence != null:
		presence.set_process(false)

	# Show black panel immediately to prevent any flash
	if level_intro_panel != null:
		level_intro_panel.z_index = 100
		level_intro_panel.visible = true
		level_intro_panel.modulate = Color(1, 1, 1, 1)

	if level_intro_text != null:
		level_intro_text.visible = false
		level_intro_text.modulate = Color(1, 1, 1, 0)

	_current_phase = Phase.DOOR_PAUSE
	_phase_timer = GameConfig.door_pause_time
	print("[TransitionController] Phase: DOOR_PAUSE")

func _advance_phase() -> void:
	match _current_phase:
		Phase.DOOR_PAUSE:
			_current_phase = Phase.LEVEL_UP
			_phase_timer = 0.0
			_run_level_up()
			print("[TransitionController] Phase: LEVEL_UP")

		Phase.FADE_IN:
			_current_phase = Phase.TEXT_HOLD
			_phase_timer = GameConfig.door_text_hold_time
			print("[TransitionController] Phase: TEXT_HOLD")

		Phase.TEXT_HOLD:
			_current_phase = Phase.GENERATING
			_phase_timer = 0.0
			_generate_new_level()
			print("[TransitionController] Phase: GENERATING")

		Phase.GENERATING:
			_current_phase = Phase.FADE_OUT
			_fade_out_text(GameConfig.door_fade_time)
			_phase_timer = GameConfig.door_fade_time * 2 # text fade + panel fade
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

	# Ensure the font and size match the UI theme
	var theme := level_intro_text.get_theme()
	if theme != null:
		var font := theme.get_font("font", "Label")
		var font_size := theme.get_font_size("font_size", "Label")
		if font != null:
			level_intro_text.add_theme_font_override("font", font)
		if font_size > 0:
			level_intro_text.add_theme_font_size_override("font_size", font_size)

	# Wait one frame for UI to settle
	await get_tree().process_frame

	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # IMPORTANT: run tween while paused
	t.tween_property(level_intro_text, "modulate:a", 1.0, fade_time)
	await t.finished

func _fade_out_text(fade_time: float) -> void:
	if level_intro_text == null or level_intro_panel == null:
		return

	# Fade out the text first
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(level_intro_text, "modulate:a", 0.0, fade_time)
	await t.finished

	# Then fade out the black panel
	var t2 := create_tween()
	t2.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t2.tween_property(level_intro_panel, "modulate:a", 0.0, fade_time)
	await t2.finished

	level_intro_panel.visible = false
	level_intro_text.visible = false

func _generate_new_level() -> void:
	if maze == null or controller == null:
		return

	# Advance difficulty
	if maze.level >= GameConfig.max_levels_before_reset:
		maze.advance_run()
	else:
		maze.level += 1

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

	_current_phase = Phase.IDLE
	print("[TransitionController] Transition complete")

func _run_level_up() -> void:
	if level_up_panel == null or game == null or game.player == null:
		print("[TransitionController] LEVEL UP SKIPPED: panel/player missing")
		return

	GameState.current = GameState.State.PAUSED

	var choices := _roll_three_upgrades(game.player)

	if level_intro_panel != null:
		level_intro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	level_up_panel.z_index = level_intro_panel.z_index + 1

	level_up_panel.show_choices(choices)

	var picked = await level_up_panel.upgrade_chosen
	var stat_name: String = picked[0]
	var amount: int = picked[1]

	_apply_upgrade(game.player, stat_name, amount)

	# Optional: persist into SaveManager’s runtime dict so wins carry it
	SaveManager.current_save_data["player_stats"] = game.player.get_stats()

	# Continue transition: now show the label text
	_current_phase = Phase.FADE_IN
	_fade_in_text(GameConfig.door_message, GameConfig.door_fade_time)
	_phase_timer = GameConfig.door_fade_time
	print("[TransitionController] Phase: FADE_IN")

func _roll_three_upgrades(player: Node) -> Array[Dictionary]:
	var stats: Dictionary = player.get_stats()
	var keys: Array = stats.keys()

	var MAX_STAT := 10
	var eligible: Array[String] = []
	for k in keys:
		var name := String(k)
		if int(stats[name]) < MAX_STAT:
			eligible.append(name)

	if eligible.is_empty():
		eligible = keys.map(func(x): return String(x))

	eligible.shuffle()

	var amount := 1
	var out: Array[Dictionary] = []
	var n: int = min(3, eligible.size())
	for i in n:
		var s := eligible[i]
		out.append({
			"stat": s,
			"amount": amount,
			"text": "+%d %s" % [amount, s]
		})
	return out

func _apply_upgrade(player: Node, stat_name: String, amount: int) -> void:
	var cur = int(player.get_stat(stat_name))
	player.set_stat(stat_name, cur + amount)
	print("[TransitionController] Applied upgrade: %s +%d (new value: %d)" % [stat_name, amount, cur + amount])