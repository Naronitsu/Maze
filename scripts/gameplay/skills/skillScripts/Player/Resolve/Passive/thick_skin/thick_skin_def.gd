extends PassiveDef
class_name ThickSkinDef

## Increased Max HP while equipped.
## Non-stacking across levels because it overwrites a keyed modifier.

@export var hp_increase_by_level: Array[float] = [1, 2, 3]  # level -> multiplier


func create_instance(owner: Node, level: int):
	return ThickSkinInstance.new(owner, self, level)
