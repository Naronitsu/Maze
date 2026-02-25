extends PassiveInstance
class_name SteadyHandsInstance


func apply() -> void:
	var stats := _get_stats()
	if stats == null:
		return

	_remove_all_keys()

	var pdef := def as SteadyHandsDef
	if pdef == null:
		return

	var decrease = 0

	if level >= 0 and level < pdef.pillar_charge_time_reduction_by_level.size():
		decrease = float(pdef.pillar_charge_time_reduction_by_level[level])
	elif pdef.pillar_charge_time_reduction_by_level.size() > 0:
		decrease = float(pdef.pillar_charge_time_reduction_by_level.back())

	var key: StringName = StringName("%s:Pillar Charge Time" % String(def.id))
	stats.set_flat(key, StringName("Pillar Charge Time"), decrease)
	applied_keys.append(key)
