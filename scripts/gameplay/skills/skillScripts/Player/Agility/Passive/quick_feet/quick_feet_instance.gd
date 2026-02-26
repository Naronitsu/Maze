extends PassiveInstance
class_name QuickFeetInstance

## Applies Step Time modifier from QuickFeetDef.


#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return

	_remove_all_keys()

	var pdef: QuickFeetDef = def as QuickFeetDef
	if pdef == null:
		return

	var base_step: float = float(st.base.get("Step Time", 0.0))
	var mult: float = 1.0
	if level >= 0 and level < pdef.step_time_multiplier_by_level.size():
		mult = float(pdef.step_time_multiplier_by_level[level])
	elif pdef.step_time_multiplier_by_level.size() > 0:
		mult = float(pdef.step_time_multiplier_by_level.back())

	var delta: float = base_step * (mult - 1.0)
	var key: StringName = StringName("%s:Step Time" % String(def.id))
	st.set_flat(key, StringName("Step Time"), delta)
	applied_keys.append(key)
#endregion
