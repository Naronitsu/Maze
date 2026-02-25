extends PassiveDef
class_name KeenAwarenessDef

## Reduces Pillar Charge Time while equipped.
## Non-stacking across levels because it overwrites a keyed modifier.

@export var fog_range_bonus_by_level: Array[float] = [20, 40, 60]  # level


func create_instance(owner: Node, level: int):
	return KeenAwarenessInstance.new(owner, self, level)
