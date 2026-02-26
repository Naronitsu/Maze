extends PassiveInstance
class_name KeenAwarenessInstance

## Applies Fog Vision Range Bonus from KeenAwarenessDef.

#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return

	_remove_all_keys()

	var pdef: KeenAwarenessDef = def as KeenAwarenessDef
	if pdef == null:
		return

	var bonus: float = 0.0
	if level >= 0 and level < pdef.fog_range_bonus_by_level.size():
		bonus = float(pdef.fog_range_bonus_by_level[level])
	elif pdef.fog_range_bonus_by_level.size() > 0:
		bonus = float(pdef.fog_range_bonus_by_level.back())

	var key: StringName = StringName("%s:Fog Vision Range Bonus" % String(def.id))
	st.set_flat(key, &"Fog Vision Range Bonus", bonus)
	applied_keys.append(key)
#endregion
