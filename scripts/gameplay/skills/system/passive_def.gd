extends SkillDef
class_name PassiveDef

func create_instance(owner: Node, level: int) -> SkillInstance:
	return PassiveInstance.new(owner, self, level)
