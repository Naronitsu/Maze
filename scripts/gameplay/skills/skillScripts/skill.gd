extends Resource
class_name Skill

@export var name: String
@export var stat: int # Use Stat enum
@export var is_passive: bool
@export var icon: Texture2D

func apply_passive(user): pass # For passive skills
func activate(user): pass      # For active skills
func upgrade(): pass       # For leveling up the skill