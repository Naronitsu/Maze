extends PassiveDef
class_name FocusedChargeDef

## Extra Pillar Charge Time reduction (stacks with Steady Hands).

#region Exported (Inspector)
@export var pillar_charge_reduction_by_level: Array[float] = [-1.0, -2.0, -3.0]
#endregion

#region Public Methods
func get_description() -> String:
	return "Further reduces how long you need to charge the pillar. Stacks with other charge-time skills. Effect improves with level."


func create_instance(owner: Node, level: int) -> FocusedChargeInstance:
	return FocusedChargeInstance.new(owner, self, level)
#endregion
