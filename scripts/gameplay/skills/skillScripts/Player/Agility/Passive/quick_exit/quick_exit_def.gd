extends PassiveDef
class_name QuickExitDef

## For a few seconds after opening a door, Step Time is greatly reduced.

#region Exported (Inspector)
@export var buff_duration: float = 2.5
@export var step_time_reduction_by_level: Array[float] = [-0.15, -0.2, -0.25]
#endregion


#region Public Methods
func get_description() -> String:
	return "For a few seconds after opening a door, your step time is greatly reduced so you can move through quickly."


func create_instance(owner: Node, level: int) -> QuickExitInstance:
	return QuickExitInstance.new(owner, self, level)
#endregion
