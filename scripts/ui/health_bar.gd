extends HBoxContainer

@export var heart_texture: Texture2D

var player: CharacterBody2D

var _last_heart_count: int = -1


func _ready() -> void:
	await get_tree().process_frame

	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("Health UI: Player not found.")
		return

	player.health_changed.connect(_on_health_changed)

	_on_health_changed(player.current_health, player.get_max_health())


func _on_health_changed(current: float, max: float) -> void:
	var current_count := int(current)
	var prev_count := get_child_count()

	if current_count == prev_count:
		return

	# Remove hearts
	if current_count < prev_count:
		for i in range(current_count, prev_count):
			var heart = get_child(i)
			if heart:
				var tween = create_tween()
				tween.tween_property(heart, "modulate:a", 0.0, 0.3)
				tween.tween_property(heart, "position:y", heart.position.y + 16, 0.3)
				tween.tween_callback(Callable(heart, "queue_free"))

	# Add hearts
	if current_count > prev_count:
		for i in range(prev_count, current_count):
			var heart := TextureRect.new()
			heart.texture = heart_texture
			heart.custom_minimum_size = Vector2(16, 16)
			heart.stretch_mode = TextureRect.STRETCH_SCALE
			heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			heart.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			heart.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			add_child(heart)
