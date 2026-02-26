extends Control

## Main menu: continue/play/settings/quit, keyboard nav, fade transition.

#region Exported (Inspector)
@export var game_scene: PackedScene
@export var fade_out_time: float = 0.35
#endregion

#region Onready
@onready
var continue_btn: Button = $CenterContainer/MainMenuContainer/UIContainer/ButtonContainer/ContinueButton
@onready
var play_btn: Button = $CenterContainer/MainMenuContainer/UIContainer/ButtonContainer/PlayButton
@onready
var settings_btn: Button = $CenterContainer/MainMenuContainer/UIContainer/ButtonContainer/SettingsButton
@onready
var quit_btn: Button = $CenterContainer/MainMenuContainer/UIContainer/ButtonContainer/QuitButton
@onready var settings_panel: Control = $PauseSettings
@onready var center_container: Control = $CenterContainer
#endregion

#region Private Fields
var _transitioning: bool = false
var _fade_rect: ColorRect
var _is_continue: bool = false
var _crt_overlay: ColorRect  # Set by scene or left null
var _crt_saved_curvature: float = 0.0
var _crt_has_saved_curvature: bool = false
#endregion


#region Lifecycle
func _ready() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRectRuntime"
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = true
	_fade_rect.modulate.a = 0.0
	add_child(_fade_rect)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.offset_left = 0
	_fade_rect.offset_top = 0
	_fade_rect.offset_right = 0
	_fade_rect.offset_bottom = 0
	_fade_rect.z_index = 999

	continue_btn.pressed.connect(_on_continue_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	if settings_panel.has_signal("back_pressed"):
		settings_panel.back_pressed.connect(_on_settings_back)

	for btn in [continue_btn, play_btn, settings_btn, quit_btn]:
		btn.mouse_entered.connect(_on_button_hover)
		btn.focus_entered.connect(_on_button_hover)
		btn.pressed.connect(_on_button_select)


#endregion


#region Signal Handlers
func _on_button_hover() -> void:
	UI_SoundPlayer.play_hover()


func _on_button_select() -> void:
	UI_SoundPlayer.play_select()


func _on_settings_pressed() -> void:
	if settings_panel == null:
		return
	_settings_set_active(true)
	if settings_panel.has_method("refresh_from_settings"):
		settings_panel.call("refresh_from_settings")


func _on_settings_back() -> void:
	_settings_set_active(false)


func _on_continue_pressed() -> void:
	_is_continue = true
	_start_game()


func _on_play_pressed() -> void:
	SaveManager.current_save_data = {}
	_is_continue = false
	if center_container.has_method("animate_fall_off_screen"):
		await center_container.animate_fall_off_screen()
	_start_game()


func _on_quit_pressed() -> void:
	get_tree().quit()


#endregion


#region Private Methods
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.echo:
		if Input.is_action_just_pressed("move_up"):
			_navigate_menu(-1)
		elif Input.is_action_just_pressed("move_down"):
			_navigate_menu(1)
		elif Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_select"):
			_activate_focused()
		elif Input.is_action_just_pressed("ui_cancel"):
			if settings_panel and settings_panel.visible:
				_on_settings_back()


func _get_menu_buttons() -> Array:
	if settings_panel and settings_panel.visible:
		return _collect_buttons_from_control(settings_panel)
	var container: Control = $CenterContainer/VBoxContainer
	var buttons: Array = []
	for child in container.get_children():
		if child is Button and child.visible and not child.disabled:
			buttons.append(child)
	return buttons


func _collect_buttons_from_control(ctrl: Control) -> Array:
	var buttons: Array = []
	for child in ctrl.get_children():
		if child is Button and child.visible and not child.disabled:
			buttons.append(child)
		elif child is Control:
			buttons += _collect_buttons_from_control(child)
	return buttons


func _navigate_menu(delta: int) -> void:
	var buttons: Array = _get_menu_buttons()
	if buttons.is_empty():
		return
	var idx: int = -1
	for i in range(buttons.size()):
		if buttons[i].has_focus():
			idx = i
			break
	if idx == -1:
		buttons[0].grab_focus()
		return
	idx = (idx + delta) % buttons.size()
	if idx < 0:
		idx = buttons.size() - 1
	buttons[idx].grab_focus()


func _activate_focused() -> void:
	var buttons: Array = _get_menu_buttons()
	for b in buttons:
		if b.has_focus():
			b.emit_signal("pressed")
			return


func _settings_set_active(active: bool) -> void:
	settings_panel.visible = active
	settings_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	)
	_set_ui_mouse_mode(active)
	play_btn.disabled = active
	continue_btn.disabled = active
	settings_btn.disabled = active
	quit_btn.disabled = active


func _cache_crt_curvature() -> void:
	if _crt_overlay == null or not (_crt_overlay.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _crt_overlay.material as ShaderMaterial
	if mat == null:
		return
	var v: Variant = mat.get_shader_parameter("curvature")
	if v is float:
		_crt_saved_curvature = float(v)
		_crt_has_saved_curvature = true


func _set_ui_mouse_mode(active: bool) -> void:
	if _crt_overlay == null or not (_crt_overlay.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _crt_overlay.material as ShaderMaterial
	if mat == null:
		return
	if active:
		if not _crt_has_saved_curvature:
			_cache_crt_curvature()
		mat.set_shader_parameter("curvature", 0.0)
	else:
		if _crt_has_saved_curvature:
			mat.set_shader_parameter("curvature", _crt_saved_curvature)
	if active:
		var btns: Array = _get_menu_buttons()
		if not btns.is_empty():
			btns[0].grab_focus()
	else:
		var main_buttons: Array = []
		var container: Control = $CenterContainer/VBoxContainer
		for child in container.get_children():
			if child is Button and child.visible and not child.disabled:
				main_buttons.append(child)
		if not main_buttons.is_empty():
			main_buttons[0].grab_focus()


func _start_game() -> void:
	if _transitioning:
		return
	_transitioning = true

	if game_scene == null:
		push_error("MainMenu: game_scene not assigned")
		_transitioning = false
		return

	if continue_btn:
		continue_btn.disabled = true
	play_btn.disabled = true
	settings_btn.disabled = true
	quit_btn.disabled = true

	var t: Tween = create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, fade_out_time)
	await t.finished

	if _is_continue:
		var save_data: Dictionary = SaveManager.load_game()
		SaveManager.current_save_data = save_data
		_is_continue = false

	await SceneLoader.change_scene_with_loading(game_scene.resource_path)
#endregion
