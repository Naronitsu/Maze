extends PassiveInstance
class_name QuickExitInstance

## After door_opened, applies Step Time reduction for a short duration.

#region Private Fields
var _buff_timer: float = 0.0
#endregion


#region Lifecycle
func on_equip() -> void:
	super.on_equip()
	if not EventBus.door_opened.is_connected(_on_door_opened):
		EventBus.door_opened.connect(_on_door_opened)
	apply()


#endregion


func on_unequip() -> void:
	_disconnect()
	super.on_unequip()


#region Signal Handlers
func _on_door_opened(_cell: Vector2i) -> void:
	var pdef: QuickExitDef = def as QuickExitDef
	if pdef != null:
		_buff_timer = pdef.buff_duration
	apply()


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
	if EventBus.door_opened.is_connected(_on_door_opened):
		EventBus.door_opened.disconnect(_on_door_opened)


func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()
	if _buff_timer <= 0.0:
		return

	var pdef: QuickExitDef = def as QuickExitDef
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
