extends PassiveDef
class_name WideEyedDef

## Fog Half Angle Bonus: wider vision cone while equipped.

#region Exported (Inspector)
@export var fog_half_angle_bonus_by_level: Array[float] = [5.0, 10.0, 15.0]
#endregion

#region Public Methods
func get_description() -> String:
	return "Widens your vision cone in the fog so you can see more to the sides. Effect improves with level."


func create_instance(owner: Node, level: int) -> WideEyedInstance:
	return WideEyedInstance.new(owner, self, level)
#endregion
