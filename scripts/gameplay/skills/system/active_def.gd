extends SkillDef
class_name ActiveDef

## Skill definition for active (cooldown) skills.

#region Exported (Inspector)
@export var cooldown: float = 1.0
#endregion

#region Public Methods
func create_instance(owner: Node, level: int) -> ActiveInstance:
	return ActiveInstance.new(owner, self, level)
#endregion
