extends Node2D

@export var radius: float = 6.0
@export var color: Color = Color(1, 0, 0, 0.95)
@export var debug_z_index: int = 999999

func _ready() -> void:
	visible = true
	z_as_relative = false

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
