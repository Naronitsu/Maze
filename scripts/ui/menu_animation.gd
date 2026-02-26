extends Control

## Animates the control falling off screen (e.g. main menu before game start).


#region Public Methods
func animate_fall_off_screen(duration: float = 0.4) -> void:
	var tween: Tween = create_tween()
	var start_pos: Vector2 = position
	var end_pos: Vector2 = Vector2(start_pos.x, get_viewport_rect().size.y + size.y)
	tween.tween_property(self, "position", end_pos, duration)
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false
#endregion
