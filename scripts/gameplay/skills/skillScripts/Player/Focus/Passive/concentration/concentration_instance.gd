extends PassiveInstance
class_name ConcentrationInstance

## Stacks while still; each stack reduces Pillar Charge Time. Stacks reset on move.

#region Private Fields
var _time_since_move: float = 0.0
var _last_applied_stacks: int = -1
#endregion

#region Public Methods
func on_player_moved() -> void:
	_time_since_move = 0.0
	_last_applied_stacks = -1
	apply()
#endregion

#region Lifecycle (tick)
func tick(delta: float) -> void:
	_time_since_move += delta
	var s: int = _current_stacks()
	if s != _last_applied_stacks:
		_last_applied_stacks = s
		apply()
#endregion

#region Private Methods
func _current_stacks() -> int:
	var pdef: ConcentrationDef = def as ConcentrationDef
	if pdef == null:
		return 0
	if pdef.seconds_per_stack <= 0.0:
		return 0
	return mini(pdef.max_stacks, int(_time_since_move / pdef.seconds_per_stack))


func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()

	if _last_applied_stacks <= 0:
		return

	var pdef: ConcentrationDef = def as ConcentrationDef
	if pdef == null:
		return

	var reduction_per_stack: float = 0.0
	if level >= 0 and level < pdef.pillar_charge_reduction_per_stack_by_level.size():
		reduction_per_stack = pdef.pillar_charge_reduction_per_stack_by_level[level]
	elif pdef.pillar_charge_reduction_per_stack_by_level.size() > 0:
		reduction_per_stack = pdef.pillar_charge_reduction_per_stack_by_level.back()

	var total: float = float(_last_applied_stacks) * reduction_per_stack
	var key: StringName = StringName("%s:Pillar Charge Time" % String(def.id))
	st.set_flat(key, &"Pillar Charge Time", total)
	applied_keys.append(key)
#endregion
