extends PassiveInstance
class_name MomentumInstance

## Temporary speed boost after consecutive steps; applies Move Speed modifier while active.

#region Public Properties
var step_streak: int = 0
var is_active: bool = false
var boost_timer: float = 0.0
#endregion


#region Public Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()
	if is_active:
		var pdef: MomentumDef = def as MomentumDef
		if pdef == null:
			return
		var key: StringName = StringName("%s:Move Speed" % String(pdef.id))
		var base_speed: float = float(st.base.get("Move Speed", 0.0))
		var mult: float = float(pdef.speed_boost)
		var delta: float = base_speed * (mult - 1.0)
		st.set_flat(key, StringName("Move Speed"), delta)
		applied_keys.append(key)


func activate_boost(_player: Player, _speed_boost_val: float, duration: float) -> void:
	is_active = true
	boost_timer = duration
	apply()


func tick(delta: float) -> void:
	if is_active:
		boost_timer -= delta
		if boost_timer <= 0.0:
			is_active = false
			boost_timer = 0.0
			step_streak = 0
			apply()


#endregion


#region Signal Handlers (unused; step logic is driven by skill_manager on_player_moved)
func _on_Player_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		step_streak += 1
		var pdef: MomentumDef = def as MomentumDef
		if pdef != null and step_streak >= pdef.steps_required:
			var player_node: Player = SceneReferences.player as Player
			if player_node != null:
				activate_boost(player_node, pdef.speed_boost, pdef.boost_duration)
	else:
		step_streak = 0
#endregion
