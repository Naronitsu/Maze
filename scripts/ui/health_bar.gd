extends HBoxContainer

## Health UI that shows full, half, and empty hearts based on current/max health (float).

@export var heart_texture: Texture2D
@export var heart_texture_half: Texture2D
@export var heart_texture_empty: Texture2D

var player: CharacterBody2D

const HEART_SIZE := Vector2(16, 16)
const EMPTY_MODULATE := Color(0.45, 0.45, 0.45, 0.85)


func _ready() -> void:
	await get_tree().process_frame

	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("Health UI: Player not found.")
		return

	player.health_changed.connect(_on_health_changed)
	_on_health_changed(player.current_health, player.get_max_health())


func _on_health_changed(current: float, max_val: float) -> void:
	var max_hearts := int(max_val)
	_ensure_heart_count(max_hearts)
	_update_heart_states(current, max_hearts)


func _ensure_heart_count(max_hearts: int) -> void:
	var current_count := get_child_count()
	if current_count == max_hearts:
		return
	# Remove extra
	if current_count > max_hearts:
		for i in range(max_hearts, current_count):
			var heart = get_child(max_hearts)
			if heart:
				var tween = create_tween()
				tween.tween_property(heart, "modulate:a", 0.0, 0.2)
				tween.tween_callback(Callable(heart, "queue_free"))
		return
	# Add missing
	for i in range(current_count, max_hearts):
		var heart := TextureRect.new()
		heart.texture = heart_texture
		heart.custom_minimum_size = HEART_SIZE
		heart.stretch_mode = TextureRect.STRETCH_SCALE
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		heart.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		add_child(heart)


func _update_heart_states(current: float, max_hearts: int) -> void:
	for i in range(max_hearts):
		if i >= get_child_count():
			break
		var heart: TextureRect = get_child(i) as TextureRect
		if heart == null:
			continue
		# Health in this heart slot: 1 = full, 0.5 = half, 0 = empty
		var health_in_slot := clampf(current - float(i), 0.0, 1.0)
		if health_in_slot >= 1.0:
			heart.texture = heart_texture
			heart.modulate = Color.WHITE
		elif health_in_slot >= 0.5:
			heart.texture = heart_texture_half if heart_texture_half else heart_texture
			heart.modulate = Color.WHITE
		else:
			heart.texture = heart_texture_empty if heart_texture_empty else heart_texture
			heart.modulate = EMPTY_MODULATE if not heart_texture_empty else Color.WHITE
