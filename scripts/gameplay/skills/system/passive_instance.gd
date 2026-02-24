extends SkillInstance
class_name PassiveInstance

func on_equip() -> void:
	apply()

func on_unequip() -> void:
	_remove_all_keys()
	_disconnect()

func set_level(new_level: int) -> void:
	level = new_level
	apply() # overwrite (non-stacking)

func apply() -> void:
	pass # override

func _disconnect() -> void:
	pass # override if you connect to signals