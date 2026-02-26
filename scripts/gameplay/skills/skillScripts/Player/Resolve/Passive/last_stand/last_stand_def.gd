extends PassiveDef
class_name LastStandDef

## When health is at or below 25% max, gain Move Speed and Regen HP/s.

#region Exported (Inspector)
@export var move_speed_bonus_by_level: Array[float] = [1.0, 2.0, 3.0]
@export var regen_bonus_by_level: Array[float] = [0.2, 0.4, 0.6]
@export var health_threshold: float = 0.25
#endregion


#region Public Methods
func get_description() -> String:
	return "When your health drops to 25%% or below, gain bonus move speed and health regen until you heal above the threshold."


func create_instance(owner: Node, level: int) -> LastStandInstance:
	return LastStandInstance.new(owner, self, level)
#endregion
