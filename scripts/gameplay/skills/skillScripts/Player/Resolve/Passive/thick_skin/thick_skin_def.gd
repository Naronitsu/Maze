extends PassiveDef
class_name ThickSkinDef

## Increased Max HP while equipped. Non-stacking; overwrites keyed modifier.

#region Exported (Inspector)
@export var hp_increase_by_level: Array[float] = [1, 2, 3]
#endregion


#region Public Methods
func get_description() -> String:
	return "Increases your max health while equipped. Effect improves with level."


func create_instance(owner: Node, level: int) -> ThickSkinInstance:
	return ThickSkinInstance.new(owner, self, level)
#endregion
