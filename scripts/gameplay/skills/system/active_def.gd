extends SkillDef
class_name ActiveDef

@export var cooldown: float = 1.0

func create_instance(owner: Node, level: int) :
	return ActiveInstance.new(owner, self, level)
