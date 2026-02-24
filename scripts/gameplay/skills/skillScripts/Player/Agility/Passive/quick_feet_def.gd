extends "res://scripts/gameplay/skills/system/passive_def.gd"
class_name QuickFeetDef

## Reduces Step Time while equipped.
## Non-stacking across levels because it overwrites a keyed modifier.

@export var step_time_multiplier_by_level: Array[float] = [1.0, 0.90, 0.85] # level -> multiplier

func create_instance(owner: Node, level: int) -> SkillInstance:
	return QuickFeetInstance.new(owner, self, level)
