## Settings menu UI for pause menu with keyboard navigation support.
##
## Provides controls for CRT effects, chromatic aberration, resolution,
## window mode, and audio volumes. Supports both mouse and keyboard navigation
## with configurable focus handling.
extends Control

signal back_pressed

@onready var back_button: Button = $Center/Panel/VBox/BackRow/BackButton
@onready var crt_toggle: CheckBox = $Center/Panel/VBox/Grid/CrtToggle
@onready var aberration_toggle: CheckBox = $Center/Panel/VBox/Grid/AberrationToggle
@onready var resolution_option: OptionButton = $Center/Panel/VBox/Grid/ResolutionOption
@onready var window_mode_option: OptionButton = $Center/Panel/VBox/Grid/WindowModeOption
@onready var master_volume: HSlider = $Center/Panel/VBox/Grid/MasterVolume
@onready var sfx_volume: HSlider = $Center/Panel/VBox/Grid/SfxVolume
@onready var minimap_size: HSlider = $Center/Panel/VBox/Grid/MinimapSize

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
	# This panel is used both in main menu (not paused) and pause menu (paused).
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Ensure all interactive controls have proper focus modes
	back_button.focus_mode = Control.FOCUS_ALL
	crt_toggle.focus_mode = Control.FOCUS_ALL
	aberration_toggle.focus_mode = Control.FOCUS_ALL
	resolution_option.focus_mode = Control.FOCUS_ALL
	window_mode_option.focus_mode = Control.FOCUS_ALL
	master_volume.focus_mode = Control.FOCUS_ALL
	sfx_volume.focus_mode = Control.FOCUS_ALL
	minimap_size.focus_mode = Control.FOCUS_ALL
	
	back_button.pressed.connect(_on_back_pressed)
	crt_toggle.toggled.connect(_on_crt_toggled)
	aberration_toggle.toggled.connect(_on_aberration_toggled)
	resolution_option.item_selected.connect(_on_resolution_selected)
	window_mode_option.item_selected.connect(_on_window_mode_selected)
	master_volume.value_changed.connect(_on_master_volume_changed)
	sfx_volume.value_changed.connect(_on_sfx_volume_changed)
	minimap_size.value_changed.connect(_on_minimap_size_changed)

	_build_resolution_options()
	_build_window_mode_options()
	_apply_current_settings()
	
	# Connect visibility changed to set focus
	visibility_changed.connect(_on_visibility_changed)

func _input(event: InputEvent) -> void:
	# Only handle input when visible
	if not visible:
		return
	
	if event is InputEventKey and event.is_pressed() and not event.echo:
		var handled := false
		
		# Check which action this key corresponds to
		if _event_matches_action(event, "move_up"):
			_navigate_menu(-1)
			handled = true
		elif _event_matches_action(event, "move_down"):
			_navigate_menu(1)
			handled = true
		elif _event_matches_action(event, "ui_accept"):
			_activate_focused()
			handled = true
		elif _event_matches_action(event, "ui_cancel"):
			# Go back to pause menu
			back_pressed.emit()
			handled = true
		elif _event_matches_action(event, "move_left"):
			# Allow Range controls to process left arrow
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Range:
				_adjust_range_value(focused, -0.1)
				handled = true
		elif _event_matches_action(event, "move_right"):
			# Allow Range controls to process right arrow
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Range:
				_adjust_range_value(focused, 0.1)
				handled = true
		
		if handled:
			if is_inside_tree():
				get_viewport().set_input_as_handled()

func _event_matches_action(event: InputEvent, action_name: String) -> bool:
	var events := InputMap.action_get_events(action_name)
	for ev in events:
		if ev is InputEventKey:
			# In Godot 4.x, physical_keycode is preferred over keycode
			var event_key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			var ev_key: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			if event_key == ev_key:
				return true
	return false

func _get_menu_controls() -> Array:
	var controls: Array = []
	# Collect all focusable interactive controls
	for control in [crt_toggle, aberration_toggle, resolution_option, window_mode_option, master_volume, sfx_volume, minimap_size, back_button]:
		if control.visible:
			# Check if control is disabled (only for controls that have this property)
			var is_disabled = false
			if control is BaseButton or control is OptionButton:
				is_disabled = control.disabled
			
			if not is_disabled:
				if control.focus_mode == Control.FOCUS_ALL or control.focus_mode == Control.FOCUS_CLICK:
					controls.append(control)
	return controls

func _navigate_menu(delta: int) -> void:
	var controls := _get_menu_controls()
	if controls.is_empty():
		return
	
	# Find focused index
	var idx := -1
	for i in range(controls.size()):
		if controls[i].has_focus():
			idx = i
			break
	
	# If none focused, focus first
	if idx == -1:
		controls[0].grab_focus()
		return
	
	# Move
	idx = (idx + delta) % controls.size()
	if idx < 0:
		idx = controls.size() - 1
	controls[idx].grab_focus()

func _activate_focused() -> void:
	var controls := _get_menu_controls()
	for c in controls:
		if c.has_focus():
			# For BaseButton subclasses (Button, CheckBox), emit pressed signal
			if c is BaseButton:
				c.emit_signal("pressed")
			return

func _adjust_range_value(range_control: Range, delta: float) -> void:
	# Adjust slider value by a percentage of its range
	var range_size = range_control.max_value - range_control.min_value
	var adj = range_size * delta
	range_control.value = clamp(range_control.value + adj, range_control.min_value, range_control.max_value)

func _on_visibility_changed() -> void:
	if visible:
		# Set focus to first control when menu becomes visible
		var controls := _get_menu_controls()
		if not controls.is_empty():
			controls[0].grab_focus()

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
	crt_toggle.set_pressed_no_signal(SettingsManager.crt_enabled)
	aberration_toggle.set_pressed_no_signal(SettingsManager.chromatic_aberration)
	master_volume.set_value_no_signal(SettingsManager.master_volume)
	sfx_volume.set_value_no_signal(SettingsManager.sfx_volume)
	minimap_size.set_value_no_signal(float(SettingsManager.minimap_size_px))

	var res_index := 0
	for i in range(RESOLUTIONS.size()):
		if RESOLUTIONS[i] == SettingsManager.resolution:
			res_index = i
			break
	resolution_option.select(res_index)

	var mode_index := 0
	for i in range(WINDOW_MODES.size()):
		if WINDOW_MODES[i] == SettingsManager.window_mode:
			mode_index = i
			break
	window_mode_option.select(mode_index)

func _on_crt_toggled(pressed: bool) -> void:
	SettingsManager.set_crt_enabled(pressed)

func _on_aberration_toggled(pressed: bool) -> void:
	SettingsManager.set_chromatic_aberration(pressed)

func _on_resolution_selected(index: int) -> void:
	var res := resolution_option.get_item_metadata(index) as Vector2i
	if res != null:
		SettingsManager.set_resolution(res)

func _on_window_mode_selected(index: int) -> void:
	var mode := window_mode_option.get_item_metadata(index) as String
	if mode != null and not mode.is_empty():
		SettingsManager.set_window_mode(mode)

func _on_master_volume_changed(value: float) -> void:
	SettingsManager.set_master_volume(value)

func _on_sfx_volume_changed(value: float) -> void:
	SettingsManager.set_sfx_volume(value)

func _on_minimap_size_changed(value: float) -> void:
	SettingsManager.set_minimap_size_px(int(round(value)))
