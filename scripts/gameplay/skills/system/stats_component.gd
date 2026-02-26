extends Node
class_name Stats

## Keyed modifier system (flat additive). Add as child "Stats" under actor (Player, etc.).

#region Exported (Inspector)
@export var base: Dictionary = {
	"Agility": 3,
	"Perception": 3,
	"Focus": 3,
	"Resolve": 3,
	"Composure": 3,
	"Step Time": 0.25,
	"Max Health": 3,
	"Move Speed": 10.0,
	"Pillar Charge Time": 12.0,
	"Fog Vision Range Per Perception": 0.0,
	"Fog Half Angle Per Perception": 0.0,
	"Fog Vision Range Bonus": 0.0,
	"Fog Half Angle Bonus": 0.0,
	"Regen Delay Seconds": 0.0,
	"Regen HP Per Second": 0.0,
}
#endregion

#region Signals
signal stat_changed(stat_name: StringName)
#endregion

#region Private Fields
var _flat: Dictionary = {}
#endregion

#region Public Methods
func set_flat(key: StringName, stat_name: StringName, value: float) -> void:
	_flat[key] = {"stat": stat_name, "value": value}
	emit_signal("stat_changed", stat_name)


func remove(key: StringName) -> void:
	if not _flat.has(key):
		return
	var stat_name: StringName = _flat[key]["stat"]
	_flat.erase(key)
	emit_signal("stat_changed", stat_name)


func set_base(stat_name: StringName, value: Variant) -> void:
	base[String(stat_name)] = value
	emit_signal("stat_changed", stat_name)


func get_value(stat_name: StringName) -> float:
	var key: String = String(stat_name)
	var v: float = float(base.get(key, 0.0))
	for entry in _flat.values():
		if entry["stat"] == stat_name:
			v += float(entry["value"])
	return v


func get_base(stat_name: StringName, default_value: Variant = 0.0) -> Variant:
	return base.get(String(stat_name), default_value)


func get_stat(stat_name: StringName) -> float:
	var total: float = float(base.get(String(stat_name), 0.0))
	for entry in _flat.values():
		if entry["stat"] == stat_name:
			total += float(entry["value"])
	return total


func get_fog_vision_range(config_range: float) -> float:
	var per: float = get_stat(&"Perception")
	var per_scale: float = get_stat(&"Fog Vision Range Per Perception")
	var bonus: float = get_stat(&"Fog Vision Range Bonus")
	return config_range + (per * per_scale) + bonus


func get_fog_half_angle_deg(config_half_angle_deg: float) -> float:
	var per: float = get_stat(&"Perception")
	var per_scale: float = get_stat(&"Fog Half Angle Per Perception")
	var bonus: float = get_stat(&"Fog Half Angle Bonus")
	return config_half_angle_deg + (per * per_scale) + bonus


func debug_dump() -> void:
	print("[Stats] base:", base)
	if "_flat" in self:
		print("[Stats] mods:", _flat)
#endregion
