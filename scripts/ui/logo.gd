extends Node2D

@export var start_scale: float = 4.0   # how large it starts
@export var zoom_time: float = 0.6
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _ready():
	scale = Vector2(start_scale, start_scale)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, zoom_time) \
	.set_trans(Tween.TRANS_CUBIC) \
	.set_ease(Tween.EASE_OUT)

	await tween.finished
	audio_stream_player_2d.play(0.0)

	
