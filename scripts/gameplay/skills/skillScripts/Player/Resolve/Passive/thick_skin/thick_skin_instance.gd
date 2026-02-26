extends PassiveInstance
class_name ThickSkinInstance

## Applies Max Health modifier from ThickSkinDef.


#region Private Methods
func apply() -> void:
	print("ThickSkinInstance apply")
	var st: Stats = _get_stats()
	if st == null:
		return

	_remove_all_keys()

	var pdef: ThickSkinDef = def as ThickSkinDef
	if pdef == null:
		return

	var increase: float = 0.0
	if level >= 0 and level < pdef.hp_increase_by_level.size():
		increase = float(pdef.hp_increase_by_level[level])
	elif pdef.hp_increase_by_level.size() > 0:
		increase = float(pdef.hp_increase_by_level.back())

	var key: StringName = StringName("%s:Max Health" % String(def.id))
	st.set_flat(key, StringName("Max Health"), increase)
	applied_keys.append(key)
#endregion
