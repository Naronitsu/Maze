extends PassiveInstance
class_name CalmRecoveryInstance


func apply() -> void:
	var stats := _get_stats()
	if stats == null:
		return

	_remove_all_keys()

	var pdef := def as CalmRecoveryDef
	if pdef == null:
		return

	var delay_reduction := 0.0
	var speed_bonus := 0.0

	if level >= 0 and level < pdef.regen_delay_reduction_by_level.size():
		delay_reduction = float(pdef.regen_delay_reduction_by_level[level])
	elif pdef.regen_delay_reduction_by_level.size() > 0:
		delay_reduction = float(pdef.regen_delay_reduction_by_level.back())

	if level >= 0 and level < pdef.regen_speed_bonus_by_level.size():
		speed_bonus = float(pdef.regen_speed_bonus_by_level[level])
	elif pdef.regen_speed_bonus_by_level.size() > 0:
		speed_bonus = float(pdef.regen_speed_bonus_by_level.back())

	# Regen delay reduction (negative because we reduce delay)
	var delay_key: StringName = StringName("%s:Regen Delay" % String(def.id))
	stats.set_flat(delay_key, &"Regen Delay Seconds", -delay_reduction)
	applied_keys.append(delay_key)

	# Regen speed increase
	var speed_key: StringName = StringName("%s:Regen Speed" % String(def.id))
	stats.set_flat(speed_key, &"Regen HP Per Second", speed_bonus)
	applied_keys.append(speed_key)
