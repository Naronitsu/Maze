extends PassiveDef
class_name CalmRecoveryDef

@export var regen_delay_reduction_by_level: Array[float] = [0.5, 1.0, 1.5]
@export var regen_speed_bonus_by_level: Array[float] = [0.5, 1.0, 2.0]


func create_instance(owner: Node, level: int):
	return CalmRecoveryInstance.new(owner, self, level)
