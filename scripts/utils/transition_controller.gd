extends Node
class_name TransitionController
## Centralized level transition orchestration
## Sequence: pause → level up (pick) → fade in text → hold → generate → fade out → resume

enum Phase {
	IDLE, DOOR_PAUSE, LEVEL_UP, FADE_IN, TEXT_HOLD, GENERATING, FADE_OUT, SETTLING, COMPLETE
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

@export var skill_pools: Array[SkillPool] = []
var _pool_by_stat: Dictionary = {}  # StringName -> SkillPool


func _ready() -> void:
	game = get_parent() as Node2D
	maze = SceneReferences.maze
	controller = SceneReferences.controller
	presence = SceneReferences.presence
	fog = SceneReferences.fog
	ui_layer = SceneReferences.ui_layer
	level_intro_panel = SceneReferences.level_intro_panel
	level_intro_text = SceneReferences.level_intro_text
	level_up_panel = SceneReferences.level_up_panel

	print("[TransitionController] skill_pools size:", skill_pools.size())

	for p in skill_pools:
		if p != null:
			_pool_by_stat[p.stat_id] = p

	print("[TransitionController] _pool_by_stat keys:", _pool_by_stat.keys())


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
			_phase_timer = GameConfig.door_fade_time * 2  # text fade + panel fade
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
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # IMPORTANT: run tween while paused
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
	EventBus.level_started.emit(game.player.cell if "cell" in game.player else Vector2i.ZERO, maze)

	_current_phase = Phase.IDLE
	print("[TransitionController] Transition complete")


func _run_level_up() -> void:
	if level_up_panel == null or game == null or game.player == null:
		print("[TransitionController] LEVEL UP SKIPPED: panel/player missing")
		return

	GameState.current = GameState.State.PAUSED

	# ----------------------------
	# Step 1: pick a stat upgrade
	# ----------------------------
	var stat_choices := _roll_three_upgrades(game.player)

	if level_intro_panel != null:
		level_intro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_up_panel.z_index = level_intro_panel.z_index + 1

	level_up_panel.show_choices(stat_choices)

	var stat_choice: Dictionary = await level_up_panel.choice_chosen
	if String(stat_choice.get("kind", "")) != "stat":
		push_warning("[TransitionController] Expected stat choice, got: %s" % str(stat_choice))
		return

	var stat_name: String = String(stat_choice.get("stat", ""))
	var amount: int = int(stat_choice.get("amount", 1))
	_apply_upgrade(game.player, stat_name, amount)

	# ----------------------------
	# Step 2: offer skills from that stat pool
	# ----------------------------
	print("[TransitionController] Stat picked:", stat_name)
	print("[TransitionController] Looking for pool key:", StringName(stat_name))

	var skill_choices := _roll_three_skills_for_stat(game.player, StringName(stat_name))

	if not skill_choices.is_empty():
		level_up_panel.show_choices(skill_choices)

		var skill_choice: Dictionary = await level_up_panel.choice_chosen
		if String(skill_choice.get("kind", "")) != "skill":
			push_warning(
				"[TransitionController] Expected skill choice, got: %s" % str(skill_choice)
			)
		else:
			_apply_skill_choice(game.player, skill_choice)

	# Continue transition: now show the label text
	_current_phase = Phase.FADE_IN
	_fade_in_text(GameConfig.door_message, GameConfig.door_fade_time)
	_phase_timer = GameConfig.door_fade_time
	print("[TransitionController] Phase: FADE_IN")


func _roll_three_upgrades(player: Node) -> Array[Dictionary]:
	var stats := player.get_node_or_null("Stats")
	if stats == null:
		push_warning("[TransitionController] Player Stats node missing")
		return []
	if not ("base" in stats):
		push_warning("[TransitionController] Stats node has no 'base' dictionary")
		return []

	# Only offer progression stats (not runtime stats)
	var upgradeable := [&"Agility", &"Perception", &"Focus", &"Resolve", &"Composure"]

	var MAX_STAT := 10
	var eligible: Array[StringName] = []
	for k in upgradeable:
		var v := float((stats.base as Dictionary).get(k, 0.0))
		if int(v) < MAX_STAT:
			eligible.append(k)

	# If everything is capped, allow all upgradeable anyway
	if eligible.is_empty():
		eligible = upgradeable.duplicate()

	eligible.shuffle()

	var amount := 1
	var out: Array[Dictionary] = []
	var n: int = min(3, eligible.size())
	for i in range(n):
		var s: StringName = eligible[i]
		out.append(
			{
				"kind": "stat",
				"stat": String(s),
				"amount": amount,
				"text": "+%d %s" % [amount, String(s)]
			}
		)
	return out


func _apply_upgrade(player: Node, stat_name: String, amount: int) -> void:
	var stats: Node = player.get_node_or_null("Stats")
	if stats == null or not stats.has_method("apply_progression_upgrade"):
		push_warning("[TransitionController] Player stats component missing or incompatible")
		return
	stats.apply_progression_upgrade(stat_name, amount)
	var cur := int(stats.get_stat(stat_name))

	print(
		(
			"[TransitionController] Applied upgrade: %s +%d (new value: %d)"
			% [stat_name, amount, cur + amount]
		)
	)


func _roll_three_skills_for_stat(player: Node, stat_id: StringName) -> Array[Dictionary]:
	print("[TransitionController] _roll_three_skills_for_stat stat_id:", stat_id)
	print("[TransitionController] available pools:", _pool_by_stat.keys())

	var pool: SkillPool = _pool_by_stat.get(stat_id, null)
	if pool == null:
		return []

	var sm := player.get_node_or_null("SkillManager")
	if sm == null:
		return []

	var candidates: Array[Dictionary] = []

	# Passives (add actives later if desired)
	for def in pool.passives:
		if def == null:
			continue

		var id: StringName = def.id

		var owned := false
		if "passive_instances" in sm:
			owned = (sm.passive_instances as Dictionary).has(id)

		var cur_level := 0
		if "levels" in sm:
			cur_level = int((sm.levels as Dictionary).get(id, 0))  # 0-based

		var label := def.display_name
		if owned:
			# cur_level is 0-based; next level (human) is (cur_level+1)+1 = cur_level+2
			label = "%s (Upgrade → %d)" % [def.display_name, cur_level + 2]
		else:
			label = "%s (New)" % def.display_name

		candidates.append(
			{"kind": "skill", "type": "passive", "skill_id": id, "def": def, "text": label}
		)

	candidates.shuffle()
	return candidates.slice(0, min(3, candidates.size()))


func _apply_skill_choice(player: Node, choice: Dictionary) -> void:
	var sm := player.get_node_or_null("SkillManager")
	if sm == null:
		return

	var kind := String(choice.get("type", ""))
	if kind != "passive":
		push_warning("[TransitionController] Unsupported skill type: %s" % kind)
		return

	var id: StringName = choice.get("skill_id", &"") as StringName
	var def: PassiveDef = choice.get("def", null) as PassiveDef
	if id == &"" or def == null:
		push_warning("[TransitionController] Bad skill choice payload: %s" % str(choice))
		return

	var owned := false
	if "passive_instances" in sm:
		owned = (sm.passive_instances as Dictionary).has(id)

	if owned:
		var cur := 0
		if "levels" in sm:
			cur = int((sm.levels as Dictionary).get(id, 0))  # 0-based
		sm.set_level(id, cur + 1)
		print("[TransitionController] Upgraded skill: %s -> %d" % [String(id), cur + 1])
	else:
		sm.equip_passive(def)
		print("[TransitionController] Equipped new skill: %s" % String(id))

	var stats := player.get_node_or_null("Stats")
	if stats and stats.has_method("debug_dump"):
		stats.call("debug_dump")


func _find_passive_def(skill_id: StringName) -> PassiveDef:
	for p in skill_pools:
		if p == null:
			continue
		for def in p.passives:
			if def != null and def.id == skill_id:
				return def
	return null
