extends Node
class_name SkillManager

## Equip/unequip + runtime instances.
## Place this as a child of an actor (Player) alongside a child node named "Stats" (StatsComponent).

const SkillDefScript = preload("res://scripts/gameplay/skills/system/skill_def.gd")
const SkillInstanceScript = preload("res://scripts/gameplay/skills/system/skill_instance.gd")
const PassiveDefScript = preload("res://scripts/gameplay/skills/system/passive_def.gd")
const ActiveDefScript = preload("res://scripts/gameplay/skills/system/active_def.gd")
const ActiveInstanceScript = preload("res://scripts/gameplay/skills/system/active_instance.gd")

@export var equipped_passives: Array[PassiveDefScript] = []
@export var equipped_actives: Array[ActiveDefScript] = []

# skill_id -> level (ZERO-BASED: 0 = Level 1)
@export var levels: Dictionary = {}  # { StringName: int }

# skill_id -> instance
var passive_instances: Dictionary = {}  # { StringName: SkillInstance }
var active_instances: Dictionary = {}  # { StringName: SkillInstance }

@onready var owner_actor := get_parent()


func _ready() -> void:
	rebuild_all()


func _process(delta: float) -> void:
	# Tick only actives (cooldowns). Passives can implement tick too.
	for inst in active_instances.values():
		(inst as SkillInstance).tick(delta)
	for inst in passive_instances.values():
		(inst as SkillInstance).tick(delta)


func get_level(skill_id: StringName) -> int:
	# ZERO-BASED default: 0 = Level 1
	return int(levels.get(skill_id, 0))


func set_level(skill_id: StringName, new_level: int) -> void:
	# new_level is ZERO-BASED
	if new_level < 0:
		new_level = 0

	levels[skill_id] = new_level

	if passive_instances.has(skill_id):
		(passive_instances[skill_id] as SkillInstance).set_level(new_level)
	if active_instances.has(skill_id):
		(active_instances[skill_id] as SkillInstance).set_level(new_level)


func rebuild_all() -> void:
	# Unequip existing
	for inst in passive_instances.values():
		(inst as SkillInstance).on_unequip()
	for inst in active_instances.values():
		(inst as SkillInstance).on_unequip()
	passive_instances.clear()
	active_instances.clear()

	# Equip passives
	for def in equipped_passives:
		_equip_def(def, true)

	# Equip actives
	for def in equipped_actives:
		_equip_def(def, false)


func equip_passive(def: PassiveDefScript, level: int = -1) -> void:
	if def == null:
		return

	# level is ZERO-BASED; allow 0.
	if level >= 0:
		levels[def.id] = level
	elif not levels.has(def.id):
		levels[def.id] = 0

	# replace if already equipped
	unequip(def.id)
	equipped_passives.append(def)
	_equip_def(def, true)


func equip_active(def: ActiveDefScript, level: int = -1) -> void:
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
		(passive_instances[skill_id] as SkillInstance).on_unequip()
		passive_instances.erase(skill_id)
	equipped_passives = equipped_passives.filter(func(d): return d.id != skill_id)

	if active_instances.has(skill_id):
		(active_instances[skill_id] as SkillInstance).on_unequip()
		active_instances.erase(skill_id)
	equipped_actives = equipped_actives.filter(func(d): return d.id != skill_id)


func activate(skill_id: StringName, context := {}) -> bool:
	if not active_instances.has(skill_id):
		return false
	var inst := active_instances[skill_id] as ActiveInstance
	return inst.try_activate(context)


func _equip_def(def: SkillDefScript, is_passive: bool) -> void:
	if def == null:
		return
	if def.id == StringName():
		push_warning("SkillDef missing id: %s" % [def.resource_path])
		return

	# Ensure every equipped skill has a level entry
	if not levels.has(def.id):
		levels[def.id] = 0

	var lvl := get_level(def.id)  # ZERO-BASED
	var inst: SkillInstance = def.create_instance(owner_actor, lvl)
	if inst == null:
		push_warning("SkillDef.create_instance returned null for %s" % [String(def.id)])
		return

	if is_passive:
		passive_instances[def.id] = inst
	else:
		active_instances[def.id] = inst

	inst.on_equip()
