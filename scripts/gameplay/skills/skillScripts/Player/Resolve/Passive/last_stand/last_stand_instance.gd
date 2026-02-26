extends PassiveInstance
class_name LastStandInstance

## Applies Move Speed and Regen HP/s when health <= threshold. Listens to player_health_changed.

#region Lifecycle
func on_equip() -> void:
	super.on_equip()
	if not EventBus.player_health_changed.is_connected(_on_health_changed):
		EventBus.player_health_changed.connect(_on_health_changed)
	_update_from_health()


func on_unequip() -> void:
	_disconnect()
	super.on_unequip()
#endregion

#region Signal Handlers
func _on_health_changed(_current: float, _max: float) -> void:
	_update_from_health()
#endregion

#region Private Methods
func _disconnect() -> void:
	if EventBus.player_health_changed.is_connected(_on_health_changed):
		EventBus.player_health_changed.disconnect(_on_health_changed)


func _update_from_health() -> void:
	var pl: Player = owner as Player
	if pl == null:
		apply()
		return
	var max_h: float = pl.get_max_health()
	if max_h <= 0.0:
		apply()
		return
	var ratio: float = pl.current_health / max_h
	var active: bool = ratio <= (def as LastStandDef).health_threshold
	_apply_if_active(active)
#endregion

#region Apply
func apply() -> void:
	var pl: Player = owner as Player
	if pl == null:
		_apply_if_active(false)
		return
	var max_h: float = pl.get_max_health()
	var active: bool = max_h > 0.0 and (pl.current_health / max_h) <= (def as LastStandDef).health_threshold
	_apply_if_active(active)


func _apply_if_active(active: bool) -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()
	if not active:
		return

	var pdef: LastStandDef = def as LastStandDef
	if pdef == null:
		return

	var move_bonus: float = 0.0
	var regen_bonus: float = 0.0
	if level >= 0 and level < pdef.move_speed_bonus_by_level.size():
		move_bonus = pdef.move_speed_bonus_by_level[level]
	elif pdef.move_speed_bonus_by_level.size() > 0:
		move_bonus = pdef.move_speed_bonus_by_level.back()
	if level >= 0 and level < pdef.regen_bonus_by_level.size():
		regen_bonus = pdef.regen_bonus_by_level[level]
	elif pdef.regen_bonus_by_level.size() > 0:
		regen_bonus = pdef.regen_bonus_by_level.back()

	var key_move: StringName = StringName("%s:Move Speed" % String(def.id))
	st.set_flat(key_move, &"Move Speed", move_bonus)
	applied_keys.append(key_move)
	var key_regen: StringName = StringName("%s:Regen HP Per Second" % String(def.id))
	st.set_flat(key_regen, &"Regen HP Per Second", regen_bonus)
	applied_keys.append(key_regen)
#endregion
