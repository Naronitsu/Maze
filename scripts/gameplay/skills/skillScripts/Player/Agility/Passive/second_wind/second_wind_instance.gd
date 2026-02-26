extends PassiveInstance
class_name SecondWindInstance

## After taking damage, applies Step Time reduction for a short duration.

#region Private Fields
var _buff_timer: float = 0.0
var _last_health: float = -1.0
#endregion

#region Lifecycle
func on_equip() -> void:
	super.on_equip()
	_last_health = -1.0
	if not EventBus.player_health_changed.is_connected(_on_health_changed):
		EventBus.player_health_changed.connect(_on_health_changed)
	apply()
#endregion

func on_unequip() -> void:
	_disconnect()
	super.on_unequip()

#region Signal Handlers
func _on_health_changed(current: float, _max: float) -> void:
	if _last_health >= 0.0 and current < _last_health:
		var pdef: SecondWindDef = def as SecondWindDef
		if pdef != null:
			_buff_timer = pdef.buff_duration
			apply()
	_last_health = current
#endregion

#region Tick
func tick(delta: float) -> void:
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_buff_timer = 0.0
			apply()
#endregion

#region Private Methods
func _disconnect() -> void:
	if EventBus.player_health_changed.is_connected(_on_health_changed):
		EventBus.player_health_changed.disconnect(_on_health_changed)


func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()
	if _buff_timer <= 0.0:
		return

	var pdef: SecondWindDef = def as SecondWindDef
	if pdef == null:
		return

	var reduction: float = 0.0
	if level >= 0 and level < pdef.step_time_reduction_by_level.size():
		reduction = pdef.step_time_reduction_by_level[level]
	elif pdef.step_time_reduction_by_level.size() > 0:
		reduction = pdef.step_time_reduction_by_level.back()

	var key: StringName = StringName("%s:Step Time" % String(def.id))
	st.set_flat(key, &"Step Time", reduction)
	applied_keys.append(key)
#endregion
