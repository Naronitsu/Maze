extends SkillInstance
class_name ActiveInstance

var cooldown_remaining: float = 0.0

func tick(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining = maxf(0.0, cooldown_remaining - delta)

func try_activate(context := {}) -> bool:
	if cooldown_remaining > 0.0:
		return false

	var adef := def as ActiveDef
	if adef == null:
		return false

	if not can_activate(context):
		return false

	activate(context)
	cooldown_remaining = adef.cooldown
	return true

func can_activate(_context := {}) -> bool:
	return true

func activate(_context := {}) -> void:
	pass # override