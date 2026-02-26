extends RefCounted
class_name SkillInstance

## Runtime instance of a skill; holds owner, def, level and applied stat keys.

#region Public Properties
var owner: Node
var def: SkillDef
var level: int
var applied_keys: Array[StringName] = []
#endregion

#region Lifecycle
func _init(p_owner: Node, p_def: SkillDef, p_level: int) -> void:
	owner = p_owner
	def = p_def
	level = p_level
#endregion

#region Public Methods
func on_equip() -> void:
	pass


func on_unequip() -> void:
	_remove_all_keys()


func set_level(new_level: int) -> void:
	level = new_level


func tick(_delta: float) -> void:
	pass
#endregion

#region Private Methods
func _get_stats() -> Stats:
	return owner.get_node_or_null("Stats") as Stats


func _remove_all_keys() -> void:
	var st: Stats = _get_stats()
	if st == null:
		applied_keys.clear()
		return
	for k in applied_keys:
		st.remove(k)
	applied_keys.clear()
#endregion
