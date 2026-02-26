extends PassiveDef
class_name StubbornDef

## Extra Max Health (stacks with Thick Skin).

#region Exported (Inspector)
@export var max_health_bonus_by_level: Array[float] = [1.0, 2.0, 3.0]
#endregion

#region Public Methods
func get_description() -> String:
	return "Increases max health further. Stacks with other health bonuses. Effect improves with level."


func create_instance(owner: Node, level: int) -> StubbornInstance:
	return StubbornInstance.new(owner, self, level)
#endregion
