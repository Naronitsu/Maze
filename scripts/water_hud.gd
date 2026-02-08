extends CanvasLayer
class_name WaterHUD

var water_system: WaterSystem = null
var water_label: Label = null

func _ready() -> void:
	layer = 11  # Above most UI
	
	# Create label
	water_label = Label.new()
	water_label.text = "Water: --"
	water_label.add_theme_font_size_override("font_size", 16)
	water_label.add_theme_color_override("font_color", Color.CYAN)
	water_label.position = Vector2(10, 10)
	add_child(water_label)
	
	call_deferred("_resolve_water_system")

func _process(_delta: float) -> void:
	if water_system == null:
		_resolve_water_system()
		return
	
	if water_label == null:
		return
	
	var amt := water_system.bucket_amount
	var cap := GameConfig.water_bucket_capacity
	var pct := (amt / cap) * 100.0 if cap > 0.0 else 0.0
	var status := "PLACED" if water_system.bucket_placed else "CARRY"
	
	water_label.text = "Water: %.1f%% [%s]" % [pct, status]
	
	# Color based on level
	if pct > 50.0:
		water_label.add_theme_color_override("font_color", Color.CYAN)
	elif pct > 25.0:
		water_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		water_label.add_theme_color_override("font_color", Color.RED)

func _resolve_water_system() -> void:
	if water_system != null:
		return
	if SceneReferences.water_system != null:
		water_system = SceneReferences.water_system as WaterSystem
