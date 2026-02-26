extends PassiveInstance
class_name FocusedChargeInstance

## Applies Pillar Charge Time reduction from FocusedChargeDef.


#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()

	var pdef: FocusedChargeDef = def as FocusedChargeDef
	if pdef == null:
		return

	var reduction: float = 0.0
	if level >= 0 and level < pdef.pillar_charge_reduction_by_level.size():
		reduction = pdef.pillar_charge_reduction_by_level[level]
	elif pdef.pillar_charge_reduction_by_level.size() > 0:
		reduction = pdef.pillar_charge_reduction_by_level.back()

	var key: StringName = StringName("%s:Pillar Charge Time" % String(def.id))
	st.set_flat(key, &"Pillar Charge Time", reduction)
	applied_keys.append(key)
#endregion
