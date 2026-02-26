extends PassiveDef
class_name SteadyBreathDef

## Regen Delay reduction (stacks with Calm Recovery).

#region Exported (Inspector)
@export var regen_delay_reduction_by_level: Array[float] = [0.3, 0.6, 1.0]
#endregion


#region Public Methods
func get_description() -> String:
	return "Reduces how long before health regen starts. Stacks with other regen-delay skills. Effect improves with level."


func create_instance(owner: Node, level: int) -> SteadyBreathInstance:
	return SteadyBreathInstance.new(owner, self, level)
#endregion
