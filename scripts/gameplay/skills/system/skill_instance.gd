extends RefCounted
class_name SkillInstance

var owner: Node
var def: SkillDef
var level: int

# Keys this instance applied into Stats (so unequip is clean)
var applied_keys: Array[StringName] = []


func _init(p_owner: Node, p_def: SkillDef, p_level: int) -> void:
	owner = p_owner
	def = p_def
	level = p_level


func on_equip() -> void:
	pass


func on_unequip() -> void:
	_remove_all_keys()


func set_level(new_level: int) -> void:
	level = new_level


func tick(_delta: float) -> void:
	pass


func _get_stats() -> Stats:
	return owner.get_node_or_null("Stats") as Stats


func _remove_all_keys() -> void:
	var stats := _get_stats()
	if stats == null:
		applied_keys.clear()
		return
	for k in applied_keys:
		stats.remove(k)
	applied_keys.clear()
