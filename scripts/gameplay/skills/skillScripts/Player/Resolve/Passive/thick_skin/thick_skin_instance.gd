extends PassiveInstance
class_name ThickSkinInstance


func apply() -> void:
	print("ThickSkinInstance apply")
	var stats := _get_stats()
	if stats == null:
		return

	_remove_all_keys()

	var pdef := def as ThickSkinDef
	if pdef == null:
		return

	# We implement this as a flat delta to Max Health, derived from base * (multiplier - 1).
	# This keeps the modifier system additive while still supporting "percent" style tuning.
	var increase = 0

	if level >= 0 and level < pdef.hp_increase_by_level.size():
		increase = float(pdef.hp_increase_by_level[level])
	elif pdef.hp_increase_by_level.size() > 0:
		increase = float(pdef.hp_increase_by_level.back())

	var key: StringName = StringName("%s:Max Health" % String(def.id))
	stats.set_flat(key, StringName("Max Health"), increase)
	applied_keys.append(key)
