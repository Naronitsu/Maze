extends PassiveInstance
class_name AlertInstance

## After presence_spawned, applies Fog Vision Range bonus for a short duration.

#region Private Fields
var _buff_timer: float = 0.0
#endregion


#region Lifecycle
func on_equip() -> void:
	super.on_equip()
	if not EventBus.presence_spawned.is_connected(_on_presence_spawned):
		EventBus.presence_spawned.connect(_on_presence_spawned)
	apply()


#endregion


func on_unequip() -> void:
	_disconnect()
	super.on_unequip()


#region Signal Handlers
func _on_presence_spawned(_cell: Vector2i) -> void:
	var pdef: AlertDef = def as AlertDef
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
	if EventBus.presence_spawned.is_connected(_on_presence_spawned):
		EventBus.presence_spawned.disconnect(_on_presence_spawned)


func apply() -> void:
	var st: Stats = _get_stats()
	if st == null:
		return
	_remove_all_keys()
	if _buff_timer <= 0.0:
		return

	var pdef: AlertDef = def as AlertDef
	if pdef == null:
		return

	var bonus: float = 0.0
	if level >= 0 and level < pdef.fog_range_bonus_by_level.size():
		bonus = pdef.fog_range_bonus_by_level[level]
	elif pdef.fog_range_bonus_by_level.size() > 0:
		bonus = pdef.fog_range_bonus_by_level.back()

	var key: StringName = StringName("%s:Fog Vision Range Bonus" % String(def.id))
	st.set_flat(key, &"Fog Vision Range Bonus", bonus)
	applied_keys.append(key)
#endregion
