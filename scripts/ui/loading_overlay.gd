extends CanvasLayer

@onready var control: Control = $Control
@onready var progress_bar: ProgressBar = $Control/CenterContainer/VBoxContainer/ProgressBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	visible = false
	control.modulate.a = 1.0


func show_loading() -> void:
	print("loading...")
	visible = true
	control.modulate.a = 1.0
	progress_bar.value = 0


func set_progress(p: float) -> void:
	print("load progress... ", p)
	progress_bar.value = clampf(p, 0.0, 1.0) * 100.0


func fade_out(duration := 0.4) -> void:
	var t := create_tween()
	t.tween_property(control, "modulate:a", 0.0, duration)
	await t.finished
	visible = false
	control.modulate.a = 1.0
