extends PassiveInstance
class_name WideEyedInstance

## Applies Fog Half Angle Bonus from WideEyedDef.

#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()

	var pdef: WideEyedDef = def as WideEyedDef
	if pdef == null:
		return

	var bonus: float = 0.0
	if level >= 0 and level < pdef.fog_half_angle_bonus_by_level.size():
		bonus = pdef.fog_half_angle_bonus_by_level[level]
	elif pdef.fog_half_angle_bonus_by_level.size() > 0:
		bonus = pdef.fog_half_angle_bonus_by_level.back()

	var key: StringName = StringName("%s:Fog Half Angle Bonus" % String(def.id))
	st.set_flat(key, &"Fog Half Angle Bonus", bonus)
	applied_keys.append(key)
#endregion
