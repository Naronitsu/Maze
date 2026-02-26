extends PassiveDef
class_name ConcentrationDef

## Gain stacks while standing still; each stack reduces Pillar Charge Time. Lose all stacks when you move.

#region Exported (Inspector)
@export var max_stacks: int = 5
@export var seconds_per_stack: float = 1.0
@export var pillar_charge_reduction_per_stack_by_level: Array[float] = [-0.5, -0.75, -1.0]
#endregion


#region Public Methods
func get_description() -> String:
	return "Stand still to build stacks (1 per second). Each stack reduces pillar charge time. All stacks are lost when you move."


func on_player_moved(skill_instance: SkillInstance, _player: Node, _event_data: Variant) -> void:
	var conc_inst: ConcentrationInstance = skill_instance as ConcentrationInstance
	if conc_inst != null:
		conc_inst.on_player_moved()


func create_instance(owner: Node, level: int) -> ConcentrationInstance:
	return ConcentrationInstance.new(owner, self, level)
#endregion
