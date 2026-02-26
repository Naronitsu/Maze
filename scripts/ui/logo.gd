extends Node2D

## Logo zoom-in and sound on ready.

#region Exported (Inspector)
@export var start_scale: float = 4.0
@export var zoom_time: float = 0.6
#endregion

#region Onready
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D
#endregion


#region Lifecycle
func _ready() -> void:
	scale = Vector2(start_scale, start_scale)

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, zoom_time)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	await tween.finished
	audio_stream_player_2d.play(0.0)
#endregion
