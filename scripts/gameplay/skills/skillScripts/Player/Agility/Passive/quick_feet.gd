extends "res://scripts/gameplay/skills/skillScripts/passive_skill.gd"
class_name QuickFeet

var step_time_reduction := 0.1

func apply_passive(user):
    # Implement Quick Feet passive effect (e.g., increase movement speed per level)
    user.set_base_stat("Step Time", user.get_base_stat("Step Time") * (1.0 - step_time_reduction)) # Example: reduce step time by 10% per level

func upgrade():
    step_time_reduction += 0.02 # Increase reduction by 2% per upgrade