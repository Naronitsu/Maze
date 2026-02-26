extends PassiveInstance
class_name SteadyBreathInstance

## Applies Regen Delay reduction from SteadyBreathDef.


#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()

	var pdef: SteadyBreathDef = def as SteadyBreathDef
	if pdef == null:
		return

	var reduction: float = 0.0
	if level >= 0 and level < pdef.regen_delay_reduction_by_level.size():
		reduction = pdef.regen_delay_reduction_by_level[level]
	elif pdef.regen_delay_reduction_by_level.size() > 0:
		reduction = pdef.regen_delay_reduction_by_level.back()

	var key: StringName = StringName("%s:Regen Delay" % String(def.id))
	st.set_flat(key, &"Regen Delay Seconds", -reduction)
	applied_keys.append(key)
#endregion
