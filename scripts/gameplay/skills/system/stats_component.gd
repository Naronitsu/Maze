extends Node
class_name Stats

## Simple keyed modifier system (flat additive for now).
## Add this as a child node named "Stats" under any actor (Player, Enemy, etc.).

@export var base: Dictionary = {
	"Agility": 3,  #speed, movement
	"Perception": 3,  #vision
	"Focus": 3,  #pillar charge etc
	"Resolve": 3,  #HP, durability, defense
	"Composure": 3,  #recovery
	"Step Time": 0.25,
	"Walk Step Time": 0.38,
	"Max Health": 3,
	"Max Stamina": 100.0,
	"Stamina Drain Per Second": 25.0,
	"Stamina Regen Per Second": 20.0,
	"Stamina Regen Delay Seconds": 0.8,
	"Stamina Regen Delay After Depleted Seconds": 1.8,
	"Move Speed": 10.0,
	"Pillar Charge Time": 12.0,
	# Fog/vision tuning (per-player scaling)
	"Fog Vision Range Per Perception": 0.0,  # world units per Perception point
	"Fog Half Angle Per Perception": 0.0,  # degrees per Perception point
	# Fog/vision passive bonuses (flat)
	"Fog Vision Range Bonus": 0.0,  # world units
	"Fog Half Angle Bonus": 0.0,  # degrees
	#Health Regen
	"Regen Delay Seconds": 0.0,
	"Regen HP Per Second": 0.0,
}
# key -> value (flat add)
var _flat: Dictionary = {}  # { StringName: float }

signal stat_changed(stat_name: StringName)


func set_flat(key: StringName, stat_name: StringName, value: float) -> void:
	# Store the stat_name in the key to make debugging easy: "skill_id:stat"
	_flat[key] = {"stat": stat_name, "value": value}
	emit_signal("stat_changed", stat_name)


func remove(key: StringName) -> void:
	if not _flat.has(key):
		return
	var stat_name: StringName = _flat[key]["stat"]
	_flat.erase(key)
	emit_signal("stat_changed", stat_name)


func set_base(stat_name: StringName, value) -> void:
	base[String(stat_name)] = value
	emit_signal("stat_changed", stat_name)


func debug_dump() -> void:
	print("[Stats] base:", base)
	if "_flat" in self:
		print("[Stats] mods:", _flat)


func get_value(stat_name: StringName) -> float:
	var key := String(stat_name)
	var v := float(base.get(key, 0.0))
	for entry in _flat.values():
		if entry["stat"] == stat_name:
			v += float(entry["value"])
	return v


func get_base(stat_name: StringName, default_value := 0.0):
	return base.get(String(stat_name), default_value)


func get_stat(stat_name: StringName) -> float:
	var total := float(base.get(String(stat_name), 0.0))
	for entry in _flat.values():
		if entry["stat"] == stat_name:
			total += float(entry["value"])
	return total


func get_fog_vision_range(config_range: float) -> float:
	var per := get_stat(&"Perception")
	var per_scale := get_stat(&"Fog Vision Range Per Perception")
	var bonus := get_stat(&"Fog Vision Range Bonus")
	return config_range + (per * per_scale) + bonus


func get_fog_half_angle_deg(config_half_angle_deg: float) -> float:
	var per := get_stat(&"Perception")
	var per_scale := get_stat(&"Fog Half Angle Per Perception")
	var bonus := get_stat(&"Fog Half Angle Bonus")
	return config_half_angle_deg + (per * per_scale) + bonus
