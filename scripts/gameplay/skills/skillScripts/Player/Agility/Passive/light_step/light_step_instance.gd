extends PassiveInstance
class_name LightStepInstance

## Applies Move Speed bonus from LightStepDef.


#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()

	var pdef: LightStepDef = def as LightStepDef
	if pdef == null:
		return

	var bonus: float = 0.0
	if level >= 0 and level < pdef.move_speed_bonus_by_level.size():
		bonus = pdef.move_speed_bonus_by_level[level]
	elif pdef.move_speed_bonus_by_level.size() > 0:
		bonus = pdef.move_speed_bonus_by_level.back()

	var key: StringName = StringName("%s:Move Speed" % String(def.id))
	st.set_flat(key, &"Move Speed", bonus)
	applied_keys.append(key)
#endregion
