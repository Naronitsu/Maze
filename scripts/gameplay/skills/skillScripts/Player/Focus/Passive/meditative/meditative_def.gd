extends PassiveDef
class_name MeditativeDef

## While you haven't moved for a few seconds, gain bonus Regen HP/s.

#region Exported (Inspector)
@export var idle_seconds_required: float = 2.0
@export var regen_bonus_by_level: Array[float] = [0.3, 0.6, 1.0]
#endregion


#region Public Methods
func get_description() -> String:
	return "After standing still for a short time, your health regen is boosted until you move again."


func on_player_moved(skill_instance: SkillInstance, _player: Node, _event_data: Variant) -> void:
	var med_inst: MeditativeInstance = skill_instance as MeditativeInstance
	if med_inst != null:
		med_inst.on_player_moved()


func create_instance(owner: Node, level: int) -> MeditativeInstance:
	return MeditativeInstance.new(owner, self, level)
#endregion
