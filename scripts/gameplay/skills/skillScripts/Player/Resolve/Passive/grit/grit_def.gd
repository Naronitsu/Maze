extends PassiveDef
class_name GritDef

## Tradeoff: +Max Health, but +Regen Delay (slower to start healing).

#region Exported (Inspector)
@export var max_health_bonus_by_level: Array[float] = [1, 2, 3]
@export var regen_delay_penalty_by_level: Array[float] = [0.5, 1.0, 1.5]
#endregion


#region Public Methods
func get_description() -> String:
	return "Increases max health but adds delay before health regen starts. A tradeoff for toughness."


func create_instance(owner: Node, level: int) -> GritInstance:
	return GritInstance.new(owner, self, level)
#endregion
