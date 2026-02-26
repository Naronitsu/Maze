extends PassiveDef
class_name CalmRecoveryDef

## Regen delay reduction and regen speed bonus while equipped.

#region Exported (Inspector)
@export var regen_delay_reduction_by_level: Array[float] = [0.5, 1.0, 1.5]
@export var regen_speed_bonus_by_level: Array[float] = [0.5, 1.0, 2.0]
#endregion


#region Public Methods
func get_description() -> String:
	return "Reduces delay before health regen starts and increases regen speed. Effect improves with level."


func create_instance(owner: Node, level: int) -> CalmRecoveryInstance:
	return CalmRecoveryInstance.new(owner, self, level)
#endregion
