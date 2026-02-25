extends Node2D

# Powerup floating sprite effect for player
# Fades out after a short duration

@export var sprite_frames: SpriteFrames
@export var anim_name: StringName = "default"
@export var fade_time: float = 1.2

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready():
	if sprite_frames:
		sprite.sprite_frames = sprite_frames
		sprite.animation = anim_name
		sprite.play()
	# Start fade out using create_tween()
	var tw = create_tween()
	tw.tween_property(sprite, "modulate:a", 0.0, fade_time).set_trans(Tween.TRANS_LINEAR).set_ease(
		Tween.EASE_IN
	)
	tw.tween_callback(Callable(self, "queue_free"))
