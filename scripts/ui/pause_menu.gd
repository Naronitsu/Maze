extends Control

#region Signals
signal resume_pressed
signal settings_pressed
signal quit_pressed
#endregion

#region Public Properties
var resume_button: Button
var settings_button: Button
var quit_button: Button
var settings_panel: Control
#endregion


#region Lifecycle
func _ready() -> void:
	print("PauseMenu: _ready() called, visible=%s" % visible)
	# ensure this UI still processes input while the scene is paused
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	# Allow child controls to receive mouse events normally.
	mouse_filter = Control.MOUSE_FILTER_PASS

	# safe lookup using find_child
	resume_button = find_child("ResumeButton", true, false) as Button
	settings_button = find_child("SettingsButton", true, false) as Button
	quit_button = find_child("QuitButton", true, false) as Button
	settings_panel = find_child("SettingsPanel", true, false) as Control

	if resume_button:
		if not resume_button.pressed.is_connected(_on_resume_pressed):
			resume_button.pressed.connect(_on_resume_pressed)
		resume_button.focus_mode = Control.FOCUS_ALL
		if not resume_button.mouse_entered.is_connected(_on_button_hover):
			resume_button.mouse_entered.connect(_on_button_hover)
		if not resume_button.focus_entered.is_connected(_on_button_hover):
			resume_button.focus_entered.connect(_on_button_hover)
		if not resume_button.pressed.is_connected(_on_button_select):
			resume_button.pressed.connect(_on_button_select)
	else:
		push_warning("PauseMenu: ResumeButton not found")

	if settings_button:
		if not settings_button.pressed.is_connected(_on_settings_pressed):
			settings_button.pressed.connect(_on_settings_pressed)
		settings_button.focus_mode = Control.FOCUS_ALL
		if not settings_button.mouse_entered.is_connected(_on_button_hover):
			settings_button.mouse_entered.connect(_on_button_hover)
		if not settings_button.focus_entered.is_connected(_on_button_hover):
			settings_button.focus_entered.connect(_on_button_hover)
		if not settings_button.pressed.is_connected(_on_button_select):
			settings_button.pressed.connect(_on_button_select)
	else:
		push_warning("PauseMenu: SettingsButton not found")

	if quit_button:
		if not quit_button.pressed.is_connected(_on_quit_pressed):
			quit_button.pressed.connect(_on_quit_pressed)
		quit_button.focus_mode = Control.FOCUS_ALL
		if not quit_button.mouse_entered.is_connected(_on_button_hover):
			quit_button.mouse_entered.connect(_on_button_hover)
		if not quit_button.focus_entered.is_connected(_on_button_hover):
			quit_button.focus_entered.connect(_on_button_hover)
		if not quit_button.pressed.is_connected(_on_button_select):
			quit_button.pressed.connect(_on_button_select)
	else:
		push_warning("PauseMenu: QuitButton not found")


#endregion


#region Signal Handlers
func _on_button_hover() -> void:
	UI_SoundPlayer.play_hover()


func _on_button_select() -> void:
	UI_SoundPlayer.play_select()

	if settings_panel:
		if not settings_panel.is_connected("back_pressed", _on_settings_back):
			settings_panel.connect("back_pressed", _on_settings_back)
		print("PauseMenu: SettingsPanel found")
	else:
		push_warning("PauseMenu: SettingsPanel not found")

	_settings_set_active(settings_panel and settings_panel.visible)

	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

	var viewport: Viewport = get_viewport()
	if viewport and not viewport.gui_focus_changed.is_connected(_on_gui_focus_changed):
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)
	print("PauseMenu: _ready() complete")


#endregion


#region Lifecycle (_input)
func _input(event: InputEvent) -> void:
	# Only handle input when visible and not consumed by a focused control
	if not visible:
		return

	if event is InputEventKey and event.is_pressed() and not event.echo:
		print(
			(
				"PauseMenu: _input() received key event - keycode: %s, physical_keycode: %s"
				% [event.keycode, event.physical_keycode]
			)
		)
		var handled: bool = false

		# Check which action this key corresponds to
		if _event_matches_action(event, "move_up"):
			print("PauseMenu: Matched move_up")
			_navigate_menu(-1)
			handled = true
		elif _event_matches_action(event, "move_down"):
			print("PauseMenu: Matched move_down")
			_navigate_menu(1)
			handled = true
		elif _event_matches_action(event, "ui_accept"):
			print("PauseMenu: Matched ui_accept")
			_activate_focused()
			handled = true
		elif _event_matches_action(event, "ui_cancel"):
			print("PauseMenu: Matched ui_cancel")
			# Close settings if open, otherwise emit resume
			if settings_panel and settings_panel.visible:
				_settings_set_active(false)
			else:
				resume_pressed.emit()
			handled = true
		elif _event_matches_action(event, "move_left"):
			print("PauseMenu: Matched move_left")
			# Allow Range controls to process left arrow
			var focused = get_viewport().gui_get_focus_owner()
			if focused is Range:
				_adjust_range_value(focused, -0.1)
				handled = true
		elif _event_matches_action(event, "move_right"):
			print("PauseMenu: Matched move_right")
			# Allow Range controls to process right arrow
			var focused = get_viewport().gui_get_focus_owner()
			if focused is Range:
				_adjust_range_value(focused, 0.1)
				handled = true

		if handled:
			print("PauseMenu: Input handled, consuming event")
			if is_inside_tree():
				get_viewport().set_input_as_handled()


#endregion


#region Private Methods
func _event_matches_action(event: InputEvent, action_name: String) -> bool:
	var events: Array = InputMap.action_get_events(action_name)
	for ev in events:
		if ev is InputEventKey:
			# In Godot 4.x, physical_keycode is preferred over keycode
			var event_key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			var ev_key = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			if event_key == ev_key:
				return true
	return false


func _on_visibility_changed() -> void:
	if visible:
		var buttons: Array = _get_menu_buttons()
		if not buttons.is_empty():
			buttons[0].grab_focus()
		else:
			push_warning("PauseMenu: No buttons found to focus")


func _on_gui_focus_changed(control: Control) -> void:
	var n: String = "null" if control == null else String(control.name)
	print("PauseMenu: GUI focus changed to: %s" % n)


#endregion


#region Private Methods (menu buttons / navigation)
func _get_menu_buttons() -> Array:
	# If settings panel active, prefer its buttons (recurses into child Controls)
	if settings_panel and settings_panel.visible:
		return _collect_buttons_from_control(settings_panel)
	# Otherwise collect top-level buttons under this PauseMenu, excluding any inside settings_panel
	var buttons: Array = []
	for b in _collect_buttons_from_control(self):
		if settings_panel != null and _is_descendant(b, settings_panel):
			continue
		buttons.append(b)
	return buttons


func _collect_buttons_from_control(ctrl: Control) -> Array:
	var buttons: Array = []
	for child in ctrl.get_children():
		# Collect all focusable, visible, interactive controls (Button, CheckBox, OptionButton, etc.)
		if child is Control and child.visible:
			# Check if control is disabled (only for controls that have this property)
			var is_disabled = false
			if child is BaseButton or child is OptionButton or child is Range:
				is_disabled = child.disabled

			if not is_disabled:
				if child.focus_mode == Control.FOCUS_ALL or child.focus_mode == Control.FOCUS_CLICK:
					# Include BaseButton subclasses and other focusable controls
					if child is BaseButton or child is OptionButton or child is Range:
						buttons.append(child)
			# Recurse into ALL Control children to find nested buttons (not just Containers)
			buttons += _collect_buttons_from_control(child)
	return buttons


func _is_descendant(node: Node, ancestor: Node) -> bool:
	if ancestor == null:
		return false
	var cur := node
	while cur:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false


func _navigate_menu(delta: int) -> void:
	var buttons := _get_menu_buttons()
	if buttons.is_empty():
		print("PauseMenu: No buttons to navigate!")
		return
	# Find focused index
	var idx := -1
	for i in range(buttons.size()):
		if buttons[i].has_focus():
			idx = i
			break
	# If none focused, focus first
	if idx == -1:
		buttons[0].grab_focus()
		return
	# Move
	idx = (idx + delta) % buttons.size()
	if idx < 0:
		idx = buttons.size() - 1
	buttons[idx].grab_focus()
	print("PauseMenu: Navigated to button: %s" % buttons[idx].name)


func _activate_focused() -> void:
	var buttons := _get_menu_buttons()
	for b in buttons:
		if b.has_focus():
			# For BaseButton subclasses (Button, CheckBox), emit pressed signal
			if b is BaseButton:
				b.emit_signal("pressed")
			# For Range controls (HSlider), allow them to process input normally
			elif b is Range:
				# Range controls handle arrow keys themselves, no activation needed
				pass
			return


func _adjust_range_value(range_control: Range, delta: float) -> void:
	# Adjust slider value by a percentage of its range
	var range_size = range_control.max_value - range_control.min_value
	var adj = range_size * delta
	range_control.value = clamp(
		range_control.value + adj, range_control.min_value, range_control.max_value
	)


func _settings_set_active(active: bool) -> void:
	if settings_panel == null:
		return
	# show/hide settings and toggle mouse_filter so clicks work only when visible
	settings_panel.visible = active
	settings_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	)

	# enable/disable main pause buttons while settings active (skip buttons inside settings panel)
	for b in _collect_buttons_from_control(self):
		if b is Button and not _is_descendant(b, settings_panel):
			b.disabled = active

	if active:
		# focus first available control in settings
		var btns := _get_menu_buttons()
		if not btns.is_empty() and btns[0].is_inside_tree():
			btns[0].grab_focus()
	else:
		# restore focus to first available button in main pause menu
		var main_buttons := _get_menu_buttons()
		if not main_buttons.is_empty() and main_buttons[0].is_inside_tree():
			main_buttons[0].grab_focus()


func _on_resume_pressed() -> void:
	resume_pressed.emit()


func _on_settings_pressed() -> void:
	settings_pressed.emit()


func _on_quit_pressed() -> void:
	quit_pressed.emit()


func _on_settings_back() -> void:
	_settings_set_active(false)
#endregion
