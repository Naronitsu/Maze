extends SkillInstance
class_name ActiveInstance

## Runtime instance for active (cooldown) skills.

#region Public Properties
var cooldown_remaining: float = 0.0
#endregion

#region Public Methods
func tick(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining = maxf(0.0, cooldown_remaining - delta)


func try_activate(context: Dictionary = {}) -> bool:
	if cooldown_remaining > 0.0:
		return false

	var adef: ActiveDef = def as ActiveDef
	if adef == null:
		return false

	if not can_activate(context):
		return false

	activate(context)
	cooldown_remaining = adef.cooldown
	return true


func can_activate(_context: Dictionary = {}) -> bool:
	return true


func activate(_context: Dictionary = {}) -> void:
	pass
#endregion
