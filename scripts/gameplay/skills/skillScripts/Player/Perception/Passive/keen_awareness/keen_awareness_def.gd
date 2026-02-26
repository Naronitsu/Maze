extends PassiveDef
class_name KeenAwarenessDef

## Fog Vision Range Bonus while equipped. Non-stacking; overwrites keyed modifier.

#region Exported (Inspector)
@export var fog_range_bonus_by_level: Array[float] = [20, 40, 60]
#endregion

#region Public Methods
func create_instance(owner: Node, level: int) -> KeenAwarenessInstance:
	return KeenAwarenessInstance.new(owner, self, level)
#endregion
