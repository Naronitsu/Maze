extends Resource
class_name SkillDef

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var category: int = 0

func create_instance(_owner: Node, _level: int):
	return null