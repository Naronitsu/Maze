extends Resource
class_name SkillDef

## Definition-only (shared data). Do NOT store runtime state (cooldowns/stacks) here.

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var category: int = 0 # optional grouping (your Stat enum etc.)

func create_instance(owner: Node, level: int) -> SkillInstance:
	return null
