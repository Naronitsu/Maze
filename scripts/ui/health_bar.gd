extends HBoxContainer

@export var heart_texture: Texture2D
@onready var player: CharacterBody2D;

func init_hearts() -> void:
	player =  $"../../../Player"

func update_hearts() -> void:
	for child in get_children():
		child.queue_free()

	for i in range(player.current_health):
		var heart := TextureRect.new()
		heart.texture = heart_texture

		# The *actual* size you want on screen
		heart.custom_minimum_size = Vector2(16, 16)

		# Make it scale the texture to the control size
		heart.stretch_mode = TextureRect.STRETCH_SCALE
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

		# Stop container from trying to give it extra space
		heart.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		heart.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		add_child(heart)
