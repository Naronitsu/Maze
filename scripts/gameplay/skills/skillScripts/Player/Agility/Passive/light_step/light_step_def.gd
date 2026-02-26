extends PassiveDef
class_name LightStepDef

## Move Speed bonus while equipped.

#region Exported (Inspector)
@export var move_speed_bonus_by_level: Array[float] = [0.5, 1.0, 1.5]
#endregion

#region Public Methods
func get_description() -> String:
	return "Increases move speed. Effect improves with level."


func create_instance(owner: Node, level: int) -> LightStepInstance:
	return LightStepInstance.new(owner, self, level)
#endregion
