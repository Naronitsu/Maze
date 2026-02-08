extends Node2D
class_name WaterDroplet

const WATER_SPRITE := preload("res://sprites/water.png")

@onready var sprite: Sprite2D = $Sprite2D

var amount: float = 0.0
var max_amount: float = 1.0
var alpha: float = 1.0
var size_multiplier: float = 1.0
var lifetime: float = 0.0
var max_lifetime: float = 0.0

func _ready() -> void:
	if sprite.texture == null:
		sprite.texture = WATER_SPRITE
	sprite.region_enabled = true
	sprite.centered = true
	_apply_visuals()

func update_visuals(p_amount: float, p_max_amount: float, p_alpha: float, p_scale: float = 1.0) -> void:
	amount = p_amount
	max_amount = maxf(p_max_amount, 0.001)
	alpha = clampf(p_alpha, 0.0, 1.0)
	size_multiplier = maxf(p_scale, 0.01)
	_apply_visuals()

func _apply_visuals() -> void:
	var ratio := clampf(amount / max_amount, 0.0, 1.0)
	var sprite_idx := 0
	if ratio > 0.66:
		sprite_idx = 2
	elif ratio > 0.33:
		sprite_idx = 1
	
	sprite.region_rect = Rect2i(sprite_idx * 32, 0, 32, 32)
	var color := sprite.modulate
	color.a = alpha
	sprite.modulate = color
	sprite.scale = Vector2(size_multiplier, size_multiplier)
