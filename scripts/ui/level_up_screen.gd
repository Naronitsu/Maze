extends Control
class_name LevelUpPanel

signal upgrade_chosen(stat_name: String, amount: int)

@onready var b1: Button = $Center/VBox/HBox/Choice1
@onready var b2: Button = $Center/VBox/HBox/Choice2
@onready var b3: Button = $Center/VBox/HBox/Choice3

var _choices: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hide()

	_bind_click(b1, 0)
	_bind_click(b2, 1)
	_bind_click(b3, 2)

func _bind_click(btn: Button, idx: int) -> void:
	btn.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton \
		and ev.button_index == MOUSE_BUTTON_LEFT \
		and ev.pressed:
			_pick(idx)
			btn.accept_event() # stop it from bubbling
	)

func show_choices(choices: Array[Dictionary]) -> void:
	# choices: [{ "stat":"Agility", "amount":1, "text":"+1 Agility" }, ...]
	_choices = choices
	_set_button(b1, 0)
	_set_button(b2, 1)
	_set_button(b3, 2)
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP

func _set_button(btn: Button, idx: int) -> void:
	if idx >= _choices.size():
		btn.disabled = true
		btn.text = ""
		return
	btn.disabled = false
	btn.text = str(_choices[idx].get("text", "???"))

func _pick(idx: int) -> void:
	if idx < 0 or idx >= _choices.size():
		return
	var c := _choices[idx]
	hide()
	upgrade_chosen.emit(String(c["stat"]), int(c["amount"]))
