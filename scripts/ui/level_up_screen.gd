extends Control
class_name LevelUpPanel

## Level-up choice panel: shows three choices and emits choice_chosen.

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
#endregion

#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	b1.pressed.connect(func() -> void: _pick(0))
	b2.pressed.connect(func() -> void: _pick(1))
	b3.pressed.connect(func() -> void: _pick(2))
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


func _pick(idx: int) -> void:
	if idx < 0 or idx >= _choices.size():
		return
	var c: Dictionary = _choices[idx]
	hide()
	choice_chosen.emit(c)
#endregion
