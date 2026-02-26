extends PassiveInstance
class_name StubbornInstance

## Applies Max Health bonus from StubbornDef.

#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()

	var pdef: StubbornDef = def as StubbornDef
	if pdef == null:
		return

	var bonus: float = 0.0
	if level >= 0 and level < pdef.max_health_bonus_by_level.size():
		bonus = pdef.max_health_bonus_by_level[level]
	elif pdef.max_health_bonus_by_level.size() > 0:
		bonus = pdef.max_health_bonus_by_level.back()

	var key: StringName = StringName("%s:Max Health" % String(def.id))
	st.set_flat(key, &"Max Health", bonus)
	applied_keys.append(key)
#endregion
