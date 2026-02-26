extends Control

## Displays player stamina as a bar. Connect to Player.stamina_changed.
## Place in bottom-left of the game UI.

@onready var progress_bar: ProgressBar = $StaminaProgress

var player: CharacterBody2D


func _ready() -> void:
	await get_tree().process_frame

	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("StaminaBar: Player not found.")
		return

	if not player.has_signal("stamina_changed"):
		push_warning("StaminaBar: Player has no stamina_changed signal.")
		return

	player.stamina_changed.connect(_on_stamina_changed)
	_on_stamina_changed(player.current_stamina, player.get_max_stamina())


func _on_stamina_changed(current: float, max_val: float) -> void:
	if progress_bar == null:
		return
	if max_val <= 0.0:
		progress_bar.value = 0
		return
	progress_bar.max_value = max_val
	progress_bar.value = current
