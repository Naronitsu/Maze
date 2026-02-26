extends Control
class_name LevelUpPanel

## Level-up choice panel: shows three choices and emits choice_chosen.

const ChoiceTooltipPopupScene = preload("res://scenes/ui/choice_tooltip_popup.tscn")

#region Signals
signal choice_chosen(choice: Dictionary)
#endregion

#region Onready
@onready var b1: Button = $Center/VBox/HBox/Choice1
@onready var b2: Button = $Center/VBox/HBox/Choice2
@onready var b3: Button = $Center/VBox/HBox/Choice3
#endregion

#region Private Fields
var _choices: Array[Dictionary] = []
var _tooltip: Control  # ChoiceTooltipPopup instance

const STAT_DESCRIPTIONS: Dictionary = {
	"Agility": "Speed and movement. Improves step time and mobility.",
	"Perception": "Awareness and vision. Improves fog range and detection.",
	"Focus": "Concentration and precision. Improves pillar charging and steady actions.",
	"Resolve": "Durability and grit. Improves max health and survival.",
	"Composure": "Calm and recovery. Improves health regen and delay.",
}
#endregion


#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	_tooltip = ChoiceTooltipPopupScene.instantiate()
	add_child(_tooltip)
	_tooltip.z_index = 100

	b1.pressed.connect(func() -> void: _pick(0))
	b2.pressed.connect(func() -> void: _pick(1))
	b3.pressed.connect(func() -> void: _pick(2))
	b1.mouse_entered.connect(_on_choice_mouse_entered.bind(0))
	b2.mouse_entered.connect(_on_choice_mouse_entered.bind(1))
	b3.mouse_entered.connect(_on_choice_mouse_entered.bind(2))
	b1.mouse_exited.connect(_on_choice_mouse_exited)
	b2.mouse_exited.connect(_on_choice_mouse_exited)
	b3.mouse_exited.connect(_on_choice_mouse_exited)


#endregion


#region Public Methods
func show_choices(choices: Array[Dictionary]) -> void:
	_choices = choices
	_set_button(b1, 0)
	_set_button(b2, 1)
	_set_button(b3, 2)

	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	b1.grab_focus()


#endregion


#region Private Methods
func _set_button(btn: Button, idx: int) -> void:
	if idx >= _choices.size():
		btn.disabled = true
		btn.text = ""
		btn.tooltip_text = ""
		return
	btn.disabled = false
	var c: Dictionary = _choices[idx]
	btn.text = str(c.get("text", "???"))
	btn.tooltip_text = _get_tooltip_for_choice(c)


func _get_tooltip_for_choice(c: Dictionary) -> String:
	var kind: Variant = c.get("kind", "")
	if kind == "stat":
		var stat_name: String = String(c.get("stat", ""))
		var amount: int = int(c.get("amount", 1))
		return "Permanently increase %s by %d." % [stat_name, amount]
	if kind == "skill" and c.has("def"):
		var def: Resource = c.get("def") as Resource
		if def != null and def.has_method("get_description"):
			return def.get_description()
		if def != null and "display_name" in def:
			return str(def.get("display_name"))
	return ""


func _on_choice_mouse_entered(idx: int) -> void:
	if idx >= _choices.size() or _tooltip == null:
		return
	var choice: Dictionary = _choices[idx]
	var kind: String = str(choice.get("kind", ""))
	var title := ""
	var affinity := "—"
	var tags := "—"
	var desc := ""
	if kind == "stat":
		title = str(choice.get("stat", "?"))
		affinity = str(choice.get("stat", "—"))
		desc = STAT_DESCRIPTIONS.get(str(choice.get("stat", "")), "No description.")
	elif kind == "skill":
		var def: Variant = choice.get("def", null)
		if def != null:
			title = def.display_name if "display_name" in def else str(choice.get("text", "?"))
			var aff: Variant = def.get("stat_affinity") if "stat_affinity" in def else null
			affinity = "—" if aff == null or str(aff) == "" else str(aff)
			var tags_val: Variant = def.get("tags") if "tags" in def else null
			var tags_arr: Array = (tags_val as Array) if tags_val is Array else []
			if tags_arr.size() > 0:
				var parts: Array[String] = []
				for t in tags_arr:
					parts.append(String(t))
				tags = ", ".join(parts)
			var desc_val: Variant = def.get("description") if "description" in def else null
			desc = "No description." if desc_val == null or str(desc_val) == "" else str(desc_val)
		else:
			title = str(choice.get("text", "?"))
	else:
		title = str(choice.get("text", "?"))
	_tooltip.set_content(title, affinity, tags, desc)
	var btn: Button = b1 if idx == 0 else (b2 if idx == 1 else b3)
	# Position under the button in our local space (we're full-screen; tooltip is our child)
	var btn_rect := btn.get_global_rect()
	var panel_global := get_global_rect().position
	_tooltip.position = (
		btn_rect.position
		- panel_global
		+ Vector2(btn_rect.size.x / 2.0 - _tooltip.size.x / 2.0, btn_rect.size.y + 6)
	)
	_tooltip.position.x = clampf(_tooltip.position.x, 0, size.x - _tooltip.size.x)
	_tooltip.position.y = minf(_tooltip.position.y, size.y - _tooltip.size.y - 8)
	_tooltip.show_tooltip()


func _on_choice_mouse_exited() -> void:
	if _tooltip != null:
		_tooltip.hide_tooltip()


func _pick(idx: int) -> void:
	if idx < 0 or idx >= _choices.size():
		return
	if _tooltip != null:
		_tooltip.hide_tooltip()
	var c: Dictionary = _choices[idx]
	hide()
	choice_chosen.emit(c)
#endregion
