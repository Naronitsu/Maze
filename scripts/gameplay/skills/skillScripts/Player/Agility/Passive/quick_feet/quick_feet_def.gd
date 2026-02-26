extends PassiveDef
class_name QuickFeetDef

## Reduces Step Time while equipped. Non-stacking; overwrites keyed modifier.

#region Exported (Inspector)
@export var step_time_multiplier_by_level: Array[float] = [0.9, 0.85, 0.8]
#endregion


#region Public Methods
func get_description() -> String:
	return "Reduces the time between steps so you move faster. Effect improves with level."


func create_instance(owner: Node, level: int) -> QuickFeetInstance:
	return QuickFeetInstance.new(owner, self, level)
#endregion
