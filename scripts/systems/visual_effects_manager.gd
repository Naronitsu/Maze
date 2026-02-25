extends Node
## Manages visual effects via EventBus signals.
## Handles screen flickers, blackouts, and other visual feedback.

@onready var game: Node2D = get_parent() if get_parent() is Node2D else null

var _is_flickering: bool = false
var _blackout_running: bool = false


func _ready() -> void:
	# Subscribe to visual effect events
	EventBus.presence_flicker.connect(_on_presence_flicker)
	EventBus.presence_caught_player.connect(_on_presence_caught)


func _on_presence_flicker() -> void:
	presence_blackout(0.55, 0.08)


func _on_presence_caught(_presence_cell: Vector2i, _player_cell: Vector2i) -> void:
	# Longer blackout when caught
	presence_blackout(1.0, 0.2)


func presence_flicker() -> void:
	if _is_flickering:
		return
	if not game.has_node("SubViewport/CanvasModulate"):
		return

	_is_flickering = true

	var cm: CanvasModulate = game.get_node("SubViewport/CanvasModulate")
	var old: Color = cm.color
	var blackout: Color = Color(old.r * 0.05, old.g * 0.05, old.b * 0.05, 1.0)

	cm.color = blackout
	await get_tree().create_timer(0.45).timeout

	cm.color = old
	_is_flickering = false


func presence_blackout(duration: float = 0.45, fade: float = 0.08) -> void:
	if _blackout_running:
		return
	_blackout_running = true

	if not game.has_node("SubViewport/Overlay/Blackout"):
		_blackout_running = false
		return

	var rect: ColorRect = game.get_node("SubViewport/Overlay/Blackout")
	rect.visible = true
	rect.modulate.a = 0.0

	var t := get_tree().create_tween()
	t.tween_property(rect, "modulate:a", 1.0, fade)
	t.tween_interval(max(0.0, duration))
	t.tween_property(rect, "modulate:a", 0.0, fade)
	await t.finished

	rect.visible = false
	_blackout_running = false
