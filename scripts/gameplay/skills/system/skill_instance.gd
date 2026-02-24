extends RefCounted
class_name SkillInstance

## Per-owner runtime skill object.
## Owns its modifier keys so unequip is always clean.

var owner: Node
var def: SkillDef
var level: int

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

func _get_stats() -> StatsComponent:
	# Convention: actor has a child node named "Stats".
	var s := owner.get_node_or_null("Stats")
	return s as StatsComponent

func _remove_all_keys() -> void:
	var stats := _get_stats()
	if stats == null:
		applied_keys.clear()
		return
	for k in applied_keys:
		stats.remove(k)
	applied_keys.clear()
