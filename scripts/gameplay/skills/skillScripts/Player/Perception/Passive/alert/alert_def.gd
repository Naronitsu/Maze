extends PassiveDef
class_name AlertDef

## For a few seconds after presence spawns, gain bonus Fog Vision Range.

#region Exported (Inspector)
@export var buff_duration: float = 5.0
@export var fog_range_bonus_by_level: Array[float] = [25.0, 40.0, 60.0]
#endregion

#region Public Methods
func get_description() -> String:
	return "When the presence spawns, your fog vision range is boosted for a few seconds. Effect improves with level."


func create_instance(owner: Node, level: int) -> AlertInstance:
	return AlertInstance.new(owner, self, level)
#endregion
