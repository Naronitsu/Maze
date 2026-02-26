extends Resource
class_name SkillPool

## Pool of passives and actives for a stat line (e.g. Agility pool).

#region Exported (Inspector)
@export var stat_id: StringName
@export var passives: Array[PassiveDef] = []
@export var actives: Array[ActiveDef] = []
#endregion
