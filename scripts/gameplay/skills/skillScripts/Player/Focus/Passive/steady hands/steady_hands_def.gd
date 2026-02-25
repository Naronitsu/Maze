extends PassiveDef
class_name SteadyHandsDef

## Reduces Pillar Charge Time while equipped.
## Non-stacking across levels because it overwrites a keyed modifier.

@export var pillar_charge_time_reduction_by_level: Array[float] = [-2, -4, -6]  # level -> multiplier


func create_instance(owner: Node, level: int):
	return SteadyHandsInstance.new(owner, self, level)
