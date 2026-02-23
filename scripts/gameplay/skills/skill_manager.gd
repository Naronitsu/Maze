extends Node
class_name SkillManager

# Import the Skill class
const Skill = preload("res://scripts/gameplay/skills/skill.gd")

var passives := {} # {skill_name: {"skill": Skill, "level": int}}
var actives := {} # {skill_name: {"skill": Skill, "level": int}}

var applied_passives := {} # {skill_name: level} to track which passives have been applied

func add_skill(skill: Skill):
    var skill_dict := passives if skill.is_passive else actives
    if skill.name in skill_dict:
        skill_dict[skill.name]["level"] += 1
    else:
        skill_dict[skill.name] = {"skill": skill, "level": 1}

func get_passives() -> Array:
    return passives.values()

func get_actives() -> Array:
    return actives.values()

func activate_skill(skill_name: String, user):
    if skill_name in actives:
        var entry = actives[skill_name]
        entry["skill"].activate(user, entry["level"])

func apply_passives(user):
    for entry in passives.values():
        entry["skill"].apply_passive(user, entry["level"])

func get_passive_levels() -> Dictionary:
    var out = {}
    for k in passives.keys():
        out[k] = passives[k]["level"]
    return out
