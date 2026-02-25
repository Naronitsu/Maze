extends HBoxContainer

@export var heart_texture: Texture2D
@onready var player: CharacterBody2D


func init_hearts() -> void:
	player = $"../../../Player"


var _last_heart_count: int = -1


func update_hearts() -> void:
	var current_count = player.current_health
	var prev_count = get_child_count()

	# Only update if heart count changed
	if current_count == prev_count:
		return

	# Animate removed hearts (if any)
	if current_count < prev_count:
		for i in range(current_count, prev_count):
			var heart = get_child(i)
			if heart:
				var tween = create_tween()
				tween.tween_property(heart, "modulate:a", 0.0, 0.5)
				tween.tween_property(heart, "position:y", heart.position.y + 32, 0.5)
				tween.tween_callback(Callable(heart, "queue_free"))

	# Add new hearts if needed
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
