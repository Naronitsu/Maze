extends Node2D
class_name RoomBounceBurst

@export var particle_count: int = 60
@export var particle_radius: float = 1.6
@export var particle_texture: Texture2D
@export var particle_size: Vector2 = Vector2(6, 6)
@export var lifetime_seconds: float = 0.85
@export var speed_min: float = 120.0
@export var speed_max: float = 220.0
@export var bounce_damping: float = 0.92

var _bounds_world: Rect2
var _age: float = 0.0

var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()


func start(bounds_world: Rect2, seed: int = 0) -> void:
	_bounds_world = bounds_world
	_age = 0.0
	visible = true
	set_process(true)

	var rng := RandomNumberGenerator.new()
	if seed == 0:
		rng.randomize()
	else:
		rng.seed = seed

	_pos = PackedVector2Array()
	_vel = PackedVector2Array()
	_pos.resize(particle_count)
	_vel.resize(particle_count)

	var center := bounds_world.get_center()
	for i in range(particle_count):
		# Spawn near center with tiny jitter.
		_pos[i] = center + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
		var a := rng.randf_range(0.0, TAU)
		var sp := rng.randf_range(speed_min, speed_max)
		_vel[i] = Vector2(cos(a), sin(a)) * sp

	queue_redraw()


func _process(dt: float) -> void:
	_age += dt
	if _age >= lifetime_seconds:
		queue_free()
		return

	# Bounce in world-space bounds.
	var min_x := _bounds_world.position.x
	var min_y := _bounds_world.position.y
	var max_x := _bounds_world.position.x + _bounds_world.size.x
	var max_y := _bounds_world.position.y + _bounds_world.size.y

	for i in range(_pos.size()):
		var p := _pos[i] + _vel[i] * dt
		var v := _vel[i]

		if p.x < min_x:
			p.x = min_x + (min_x - p.x)
			v.x = -v.x * bounce_damping
		elif p.x > max_x:
			p.x = max_x - (p.x - max_x)
			v.x = -v.x * bounce_damping

		if p.y < min_y:
			p.y = min_y + (min_y - p.y)
			v.y = -v.y * bounce_damping
		elif p.y > max_y:
			p.y = max_y - (p.y - max_y)
			v.y = -v.y * bounce_damping

		_pos[i] = p
		_vel[i] = v

	queue_redraw()


func _draw() -> void:
	if _pos.is_empty():
		return

	var alpha := clampf(1.0 - (_age / maxf(lifetime_seconds, 0.001)), 0.0, 1.0)
	var c := Color(1, 1, 1, alpha)
	var tex := particle_texture
	var use_tex := tex != null
	var size := particle_size
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(particle_radius * 2.0, particle_radius * 2.0)

	# If we are top-level at origin, local==world. Otherwise transform.
	for i in range(_pos.size()):
		var lp := to_local(_pos[i])
		if use_tex:
			draw_texture_rect(tex, Rect2(lp - size * 0.5, size), false, c)
		else:
			draw_circle(lp, particle_radius, c)
