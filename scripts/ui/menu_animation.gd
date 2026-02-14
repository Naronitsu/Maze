extends Control

func animate_fall_off_screen(duration: float = 0.4) -> void:
	# Animate the Control node falling off the screen (downwards)
	var tween := create_tween()
	var start_pos := position
	var end_pos := Vector2(start_pos.x, get_viewport_rect().size.y + size.y)
	tween.tween_property(self, "position", end_pos, duration)
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false
