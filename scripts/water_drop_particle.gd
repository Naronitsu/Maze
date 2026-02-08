extends Node2D
class_name WaterDropParticle

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 1.0
var _age: float = 0.0
var _is_rising: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	modulate.a = 1.0
	print("[Drop] Ready at %s (position will be set in spawn_falling/rising)" % [global_position])

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	global_position += velocity * delta

	# Fade out as age increases
	var fade := 1.0 - (_age / lifetime)
	modulate.a = fade

	# Gravity on falling drops, acceleration on rising
	if _is_rising:
		velocity.y -= 8.0 * delta  # Upward acceleration + drag
	else:
		velocity.y += 10.0 * delta  # Downward gravity

func spawn_falling(world_pos: Vector2) -> void:
	"""Spawn a drop falling from bucket position"""
	global_position = world_pos
	_is_rising = false
	velocity = Vector2(randf_range(-2.0, 2.0), 0.5)  # Slower drift, slight fall
	lifetime = randf_range(4.0, 6.0)  # MUCH longer (4-6 seconds)
	if sprite:
		sprite.scale = Vector2(1.5, 1.5)  # MUCH LARGER to be visible
		sprite.modulate = Color(0.3, 0.6, 1.0, 0.95)  # Bright cyan
	print("[Drop] spawn_falling at %s, lifetime %.2f" % [global_position, lifetime])

func spawn_rising(world_pos: Vector2) -> void:
	"""Spawn vapor rising from puddle"""
	global_position = world_pos
	_is_rising = true
	velocity = Vector2(randf_range(-1.0, 1.0), randf_range(2.0, 4.0))
	lifetime = randf_range(1.0, 1.8)
	if sprite:
		sprite.scale = Vector2(1.0, 1.0)  # LARGER
		sprite.modulate = Color(0.7, 0.9, 1.0, 0.5)  # Light cyan, semi-transparent
	print("[Drop] spawn_rising at %s, lifetime %.2f" % [global_position, lifetime])
