extends PassiveDef
class_name MomentumDef

## Gain a temporary speed boost after moving several cells in a row without stopping.

#region Exported (Inspector)
@export var steps_required: int = 3
@export var speed_boost: float = 1.25
@export var boost_duration: float = 1.0
#endregion


#region Public Methods
func get_description() -> String:
	return "Gain a speed boost after moving %d steps in a row without stopping." % steps_required


func on_player_moved(skill_instance: MomentumInstance, _player: Node, _event_data: Variant) -> void:
	if not skill_instance.is_active:
		skill_instance.step_streak += 1
		if skill_instance.step_streak >= steps_required:
			skill_instance.activate_boost(_player as Player, speed_boost, boost_duration)
	else:
		skill_instance.step_streak = 0


func create_instance(owner: Node, level: int) -> MomentumInstance:
	return MomentumInstance.new(owner, self, level)
#endregion
