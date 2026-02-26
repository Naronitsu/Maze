extends PassiveDef
class_name SecondWindDef

## For a few seconds after taking damage, Step Time is reduced.

#region Exported (Inspector)
@export var buff_duration: float = 3.0
@export var step_time_reduction_by_level: Array[float] = [-0.05, -0.08, -0.12]
#endregion


#region Public Methods
func get_description() -> String:
	return "When you take damage, your step time is reduced for a few seconds so you can escape. Effect improves with level."


func create_instance(owner: Node, level: int) -> SecondWindInstance:
	return SecondWindInstance.new(owner, self, level)
#endregion
