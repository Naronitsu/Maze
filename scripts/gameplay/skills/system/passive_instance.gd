extends SkillInstance
class_name PassiveInstance

## Runtime instance for passive skills; apply/remove modifiers on equip/unequip.


#region Public Methods
func on_equip() -> void:
	apply()


func on_unequip() -> void:
	_remove_all_keys()
	_disconnect()


func set_level(new_level: int) -> void:
	level = new_level
	apply()


func apply() -> void:
	pass


func _disconnect() -> void:
	pass
#endregion
