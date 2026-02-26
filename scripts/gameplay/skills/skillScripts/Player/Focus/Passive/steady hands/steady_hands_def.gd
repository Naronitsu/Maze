extends PassiveDef
class_name SteadyHandsDef

## Reduces Pillar Charge Time while equipped. Non-stacking; overwrites keyed modifier.

#region Exported (Inspector)
@export var pillar_charge_time_reduction_by_level: Array[float] = [-2, -4, -6]
#endregion

#region Public Methods
func create_instance(owner: Node, level: int) -> SteadyHandsInstance:
	return SteadyHandsInstance.new(owner, self, level)
#endregion
