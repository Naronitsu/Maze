extends Node
class_name SkillManager

## Equip/unequip + runtime instances. Child of actor (Player) alongside "Stats" (Stats).

#region Constants
const SkillDefScript: GDScript = preload("res://scripts/gameplay/skills/system/skill_def.gd")
const SkillInstanceScript: GDScript = preload("res://scripts/gameplay/skills/system/skill_instance.gd")
const PassiveDefScript: GDScript = preload("res://scripts/gameplay/skills/system/passive_def.gd")
const ActiveDefScript: GDScript = preload("res://scripts/gameplay/skills/system/active_def.gd")
const ActiveInstanceScript: GDScript = preload("res://scripts/gameplay/skills/system/active_instance.gd")
#endregion

#region Exported (Inspector)
@export var equipped_passives: Array[PassiveDef] = []
@export var equipped_actives: Array[ActiveDef] = []
@export var levels: Dictionary = {}  # skill_id (StringName) -> level (int, ZERO-BASED)
#endregion

#region Public Properties
var passive_instances: Dictionary = {}
var active_instances: Dictionary = {}
#endregion

#region Onready
@onready var owner_actor: Node = get_parent()
#endregion

#region Lifecycle
func _ready() -> void:
	rebuild_all()


func _process(delta: float) -> void:
	for inst in active_instances.values():
		(inst as SkillInstance).tick(delta)
	for inst in passive_instances.values():
		(inst as SkillInstance).tick(delta)
#endregion

#region Public Methods
func get_level(skill_id: StringName) -> int:
	return int(levels.get(skill_id, 0))


func set_level(skill_id: StringName, new_level: int) -> void:
	if new_level < 0:
		new_level = 0
	levels[skill_id] = new_level
	if passive_instances.has(skill_id):
		(passive_instances[skill_id] as SkillInstance).set_level(new_level)
	if active_instances.has(skill_id):
		(active_instances[skill_id] as SkillInstance).set_level(new_level)


func rebuild() -> void:
	rebuild_all()


func rebuild_all() -> void:
	for inst in passive_instances.values():
		(inst as SkillInstance).on_unequip()
	for inst in active_instances.values():
		(inst as SkillInstance).on_unequip()
	passive_instances.clear()
	active_instances.clear()

	for def in equipped_passives:
		_equip_def(def, true)
	for def in equipped_actives:
		_equip_def(def, false)


func equip_passive(def: PassiveDef, level: int = -1) -> void:
	if def == null:
		return
	if level >= 0:
		levels[def.id] = level
	elif not levels.has(def.id):
		levels[def.id] = 0
	unequip(def.id)
	equipped_passives.append(def)
	_equip_def(def, true)


func equip_active(def: ActiveDef, level: int = -1) -> void:
	if def == null:
		return
	if level >= 0:
		levels[def.id] = level
	elif not levels.has(def.id):
		levels[def.id] = 0
	unequip(def.id)
	equipped_actives.append(def)
	_equip_def(def, false)


func unequip(skill_id: StringName) -> void:
	if passive_instances.has(skill_id):
		var inst: SkillInstance = passive_instances[skill_id]
		inst.on_unequip()
		passive_instances.erase(skill_id)
	if active_instances.has(skill_id):
		var inst: SkillInstance = active_instances[skill_id]
		inst.on_unequip()
		active_instances.erase(skill_id)
#endregion

#region Private Methods
func _equip_def(def: SkillDef, is_passive: bool) -> void:
	if def == null:
		return
	var lvl: int = get_level(def.id)
	if is_passive:
		var inst: PassiveInstance = (def as PassiveDef).create_instance(owner_actor, lvl)
		inst.on_equip()
		passive_instances[def.id] = inst
	else:
		var inst: ActiveInstance = (def as ActiveDef).create_instance(owner_actor, lvl)
		inst.on_equip()
		active_instances[def.id] = inst
#endregion
