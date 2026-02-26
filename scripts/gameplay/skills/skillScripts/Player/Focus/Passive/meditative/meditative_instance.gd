extends PassiveInstance
class_name MeditativeInstance

## Applies Regen HP/s bonus while idle (no move) for required seconds.

#region Private Fields
var _time_since_move: float = 0.0
var _last_applied_active: bool = false
#endregion

#region Public Methods
func on_player_moved() -> void:
	_time_since_move = 0.0
	_last_applied_active = false
	apply()
#endregion

#region Lifecycle (tick)
func tick(delta: float) -> void:
	_time_since_move += delta
	var pdef: MeditativeDef = def as MeditativeDef
	var active: bool = pdef != null and _time_since_move >= pdef.idle_seconds_required
	if active != _last_applied_active:
		_last_applied_active = active
		apply()
#endregion

#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()
	if not _last_applied_active:
		return

	var pdef: MeditativeDef = def as MeditativeDef
	if pdef == null:
		return

	var bonus: float = 0.0
	if level >= 0 and level < pdef.regen_bonus_by_level.size():
		bonus = pdef.regen_bonus_by_level[level]
	elif pdef.regen_bonus_by_level.size() > 0:
		bonus = pdef.regen_bonus_by_level.back()

	var key: StringName = StringName("%s:Regen HP Per Second" % String(def.id))
	st.set_flat(key, &"Regen HP Per Second", bonus)
	applied_keys.append(key)
#endregion
