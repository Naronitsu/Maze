extends PassiveInstance
class_name SteadyHandsInstance

## Applies Pillar Charge Time modifier from SteadyHandsDef.

#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return

	_remove_all_keys()

	var pdef: SteadyHandsDef = def as SteadyHandsDef
	if pdef == null:
		return

	var decrease: float = 0.0
	if level >= 0 and level < pdef.pillar_charge_time_reduction_by_level.size():
		decrease = float(pdef.pillar_charge_time_reduction_by_level[level])
	elif pdef.pillar_charge_time_reduction_by_level.size() > 0:
		decrease = float(pdef.pillar_charge_time_reduction_by_level.back())

	var key: StringName = StringName("%s:Pillar Charge Time" % String(def.id))
	st.set_flat(key, StringName("Pillar Charge Time"), decrease)
	applied_keys.append(key)
#endregion
