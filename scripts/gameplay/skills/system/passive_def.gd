extends SkillDef
class_name PassiveDef

## Stat this skill belongs to (e.g. &"Agility"). Used for pool display and synergy.
@export var stat_affinity: StringName = &""
## Tags for synergy: skills sharing tags with equipped skills get higher offer weight.
@export var tags: Array[StringName] = []
## Multiplier for offer weight (1.0 = normal, higher = more likely when rolling).
@export var rarity_weight: float = 1.0
## Shown in the level-up hover tooltip.
@export var description: String = ""


#region Public Methods
func create_instance(owner: Node, level: int) -> PassiveInstance:
	return PassiveInstance.new(owner, self, level)
#endregion
