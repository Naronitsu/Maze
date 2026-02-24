extends Node
class_name Stats

## Simple keyed modifier system (flat additive for now).
## Add this as a child node named "Stats" under any actor (Player, Enemy, etc.).

@export var base: Dictionary = {
	"Agility": 3,
	"Perception": 3,
	"Focus": 3,
	"Resolve": 3,
	"Composure": 3,

	"Step Time": 0.25,
	"Max Health": 3,
	"Move Speed": 10.0,
}
# key -> value (flat add)
var _flat: Dictionary = {} # { StringName: float }

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

func get_value(stat_name: StringName) -> float:
	var v := float(base.get(String(stat_name), 0.0))
	for entry in _flat.values():
		if entry["stat"] == stat_name:
			v += float(entry["value"])
	return v

func set_base(stat_name: StringName, value) -> void:
	base[String(stat_name)] = value
	emit_signal("stat_changed", stat_name)
	
func get_base(stat_name: StringName, default_value := 0.0):
	return base.get(stat_name, default_value)

func get_stat(stat_name: StringName) -> float:
	var total := float(base.get(stat_name, 0.0))
	for entry in _flat.values():
		if entry["stat"] == stat_name:
			total += float(entry["value"])
	return total

func debug_dump() -> void:
	print("[Stats] base:", base)
	if "_flat" in self:
		print("[Stats] mods:", _flat)
