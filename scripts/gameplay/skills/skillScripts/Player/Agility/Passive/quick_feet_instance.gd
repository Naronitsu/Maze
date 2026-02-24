extends "res://scripts/gameplay/skills/system/passive_instance.gd"
class_name QuickFeetInstance

func apply() -> void:
	var stats := _get_stats()
	if stats == null:
		return

	_remove_all_keys()

	var pdef := def as QuickFeetDef
	if pdef == null:
		return

	# We implement this as a flat delta to Step Time, derived from base * (multiplier - 1).
	# This keeps the modifier system additive while still supporting "percent" style tuning.
	var base_step := float(stats.base.get("Step Time", 0.0))
	var mult := 1.0
	if level >= 0 and level < pdef.step_time_multiplier_by_level.size():
		mult = float(pdef.step_time_multiplier_by_level[level])
	elif pdef.step_time_multiplier_by_level.size() > 0:
		mult = float(pdef.step_time_multiplier_by_level.back())

	var delta := base_step * (mult - 1.0) # negative reduces step time
	var key: StringName = StringName("%s:Step Time" % String(def.id))
	stats.set_flat(key, StringName("Step Time"), delta)
	applied_keys.append(key)
