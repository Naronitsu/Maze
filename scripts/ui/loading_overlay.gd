extends CanvasLayer

## Full-screen loading overlay with progress bar; used by SceneLoader.

#region Onready
@onready var control: Control = $Control
@onready var progress_bar: ProgressBar = $Control/CenterContainer/VBoxContainer/ProgressBar
#endregion

#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	visible = false
	control.modulate.a = 1.0
#endregion

#region Public Methods
func show_loading() -> void:
	print("loading...")
	visible = true
	control.modulate.a = 1.0
	progress_bar.value = 0


func set_progress(p: float) -> void:
	print("load progress... ", p)
	progress_bar.value = clampf(p, 0.0, 1.0) * 100.0


func fade_out(duration: float = 0.4) -> void:
	var t: Tween = create_tween()
	t.tween_property(control, "modulate:a", 0.0, duration)
	await t.finished
	visible = false
	control.modulate.a = 1.0
#endregion
