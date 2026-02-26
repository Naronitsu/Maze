extends PassiveInstance
class_name GritInstance

## Applies +Max Health and +Regen Delay (tradeoff).


#region Private Methods
func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()

	var pdef: GritDef = def as GritDef
	if pdef == null:
		return

	var hp_bonus: float = 0.0
	var delay_penalty: float = 0.0
	if level >= 0 and level < pdef.max_health_bonus_by_level.size():
		hp_bonus = pdef.max_health_bonus_by_level[level]
	elif pdef.max_health_bonus_by_level.size() > 0:
		hp_bonus = pdef.max_health_bonus_by_level.back()
	if level >= 0 and level < pdef.regen_delay_penalty_by_level.size():
		delay_penalty = pdef.regen_delay_penalty_by_level[level]
	elif pdef.regen_delay_penalty_by_level.size() > 0:
		delay_penalty = pdef.regen_delay_penalty_by_level.back()

	var key_hp: StringName = StringName("%s:Max Health" % String(def.id))
	st.set_flat(key_hp, &"Max Health", hp_bonus)
	applied_keys.append(key_hp)
	var key_delay: StringName = StringName("%s:Regen Delay" % String(def.id))
	st.set_flat(key_delay, &"Regen Delay Seconds", delay_penalty)
	applied_keys.append(key_delay)
#endregion
