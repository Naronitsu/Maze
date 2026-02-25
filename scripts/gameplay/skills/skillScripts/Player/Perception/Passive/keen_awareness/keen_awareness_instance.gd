extends PassiveInstance
class_name KeenAwarenessInstance


func apply() -> void:
	var stats := _get_stats()
	if stats == null:
		return

	_remove_all_keys()

	var pdef := def as KeenAwarenessDef
	if pdef == null:
		return

	var bonus := 0.0

	if level >= 0 and level < pdef.fog_range_bonus_by_level.size():
		bonus = float(pdef.fog_range_bonus_by_level[level])
	elif pdef.fog_range_bonus_by_level.size() > 0:
		bonus = float(pdef.fog_range_bonus_by_level.back())

	var key: StringName = StringName("%s:Fog Vision Range Bonus" % String(def.id))

	stats.set_flat(key, &"Fog Vision Range Bonus", bonus)

	applied_keys.append(key)
