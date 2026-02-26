extends Resource
class_name SkillDef

## Base resource for a skill definition. Subclasses: PassiveDef, ActiveDef.

#region Exported (Inspector)
@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var category: int = 0
#endregion

#region Public Methods
func create_instance(_owner: Node, _level: int) -> SkillInstance:
	return null
#endregion
