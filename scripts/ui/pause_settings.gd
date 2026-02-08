extends Control

signal back_pressed

# Access the SettingsManager autoload singleton
@onready var settings_manager: Node = get_node("/root/SettingsManager")

@onready var back_button: Button = $Center/Panel/VBox/BackRow/BackButton
@onready var crt_toggle: CheckBox = $Center/Panel/VBox/Grid/CrtToggle
@onready var aberration_toggle: CheckBox = $Center/Panel/VBox/Grid/AberrationToggle
@onready var resolution_option: OptionButton = $Center/Panel/VBox/Grid/ResolutionOption
@onready var window_mode_option: OptionButton = $Center/Panel/VBox/Grid/WindowModeOption
@onready var master_volume: HSlider = $Center/Panel/VBox/Grid/MasterVolume
@onready var sfx_volume: HSlider = $Center/Panel/VBox/Grid/SfxVolume

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 540),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

const WINDOW_MODES: Array[String] = [
	"windowed",
	"fullscreen",
	"windowed_fullscreen"
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	back_button.pressed.connect(_on_back_pressed)
	crt_toggle.toggled.connect(_on_crt_toggled)
	aberration_toggle.toggled.connect(_on_aberration_toggled)
	resolution_option.item_selected.connect(_on_resolution_selected)
	window_mode_option.item_selected.connect(_on_window_mode_selected)
	master_volume.value_changed.connect(_on_master_volume_changed)
	sfx_volume.value_changed.connect(_on_sfx_volume_changed)

	_build_resolution_options()
	_build_window_mode_options()
	_apply_current_settings()

func refresh_from_settings() -> void:
	_apply_current_settings()

func _on_back_pressed() -> void:
	back_pressed.emit()

func _build_resolution_options() -> void:
	resolution_option.clear()
	for res in RESOLUTIONS:
		var label := "%dx%d" % [res.x, res.y]
		resolution_option.add_item(label)
		resolution_option.set_item_metadata(resolution_option.item_count - 1, res)

func _build_window_mode_options() -> void:
	window_mode_option.clear()
	window_mode_option.add_item("Windowed")
	window_mode_option.add_item("Fullscreen")
	window_mode_option.add_item("Windowed Fullscreen")
	for i in range(WINDOW_MODES.size()):
		window_mode_option.set_item_metadata(i, WINDOW_MODES[i])

func _apply_current_settings() -> void:
	crt_toggle.set_pressed_no_signal(settings_manager.crt_enabled)
	aberration_toggle.set_pressed_no_signal(settings_manager.chromatic_aberration)
	master_volume.set_value_no_signal(settings_manager.master_volume)
	sfx_volume.set_value_no_signal(settings_manager.sfx_volume)

	var res_index := 0
	for i in range(RESOLUTIONS.size()):
		if RESOLUTIONS[i] == settings_manager.resolution:
			res_index = i
			break
	resolution_option.select(res_index)

	var mode_index := 0
	for i in range(WINDOW_MODES.size()):
		if WINDOW_MODES[i] == settings_manager.window_mode:
			mode_index = i
			break
	window_mode_option.select(mode_index)

func _on_crt_toggled(pressed: bool) -> void:
	settings_manager.set_crt_enabled(pressed)

func _on_aberration_toggled(pressed: bool) -> void:
	settings_manager.set_chromatic_aberration(pressed)

func _on_resolution_selected(index: int) -> void:
	var res: Variant = resolution_option.get_item_metadata(index)
	if res is Vector2i:
		settings_manager.set_resolution(res)

func _on_window_mode_selected(index: int) -> void:
	var mode: Variant = window_mode_option.get_item_metadata(index)
	if typeof(mode) == TYPE_STRING:
		settings_manager.set_window_mode(mode)

func _on_master_volume_changed(value: float) -> void:
	settings_manager.set_master_volume(value)

func _on_sfx_volume_changed(value: float) -> void:
	settings_manager.set_sfx_volume(value)
