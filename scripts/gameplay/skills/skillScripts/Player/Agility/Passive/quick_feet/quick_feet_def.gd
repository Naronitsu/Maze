extends PassiveDef
class_name QuickFeetDef

## Reduces Step Time while equipped.
## Non-stacking across levels because it overwrites a keyed modifier.

@export var step_time_multiplier_by_level: Array[float] = [0.9, 0.85, 0.8] # level -> multiplier

func create_instance(owner: Node, level: int):
	return QuickFeetInstance.new(owner, self, level)
