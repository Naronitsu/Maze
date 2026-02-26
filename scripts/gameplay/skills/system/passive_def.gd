extends SkillDef
class_name PassiveDef

## Skill definition for passive skills.

#region Public Methods
func create_instance(owner: Node, level: int) -> PassiveInstance:
	return PassiveInstance.new(owner, self, level)
#endregion
