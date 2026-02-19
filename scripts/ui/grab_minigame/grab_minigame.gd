extends Control
class_name GrabMinigame

signal escaped
signal failed

@export var gravity := 900.0          # px/s^2
@export var lift_accel := 1400.0      # px/s^2 while holding Q
@export var max_speed := 900.0        # clamp vertical speed

@export var time_in_safe_to_escape := 2.8
@export var safe_margin := 26.0       # distance from bounds considered "safe band"

@export var trail_max_points := 40
@export var trail_point_every := 0.03

@export var head_offset := Vector2(0, -60)
@export var clamp_margin := 12.0

# Difficulty: bounds slowly close in over time
@onready var viewport: SubViewport = $UIViewport
@onready var mg: Control = $UIViewport/Root/minigame
@onready var pixel: Control = $UIViewport/Root/minigame/pixel
@onready var upper: Control = $UIViewport/Root/minigame/upperBound
@onready var lower: Control = $UIViewport/Root/minigame/lowerBound
@onready var trail: Line2D = $UIViewport/Root/minigame/trail
@onready var status_label: Label = $UIViewport/Root/Panel/StatusLabel

@onready var pixel_rain: GPUParticles2D = $PixelRain

@onready var output: TextureRect = $UIOutput

@export var min_gap := 40.0

@export var shake_start_dist := 80.0
@export var shake_max_px := 10.0
@export var shake_freq := 28.0
@export var shake_smooth := 18.0

var _mg_base_pos := Vector2.ZERO
var _shake_time := 0.0
var _shake_offset := Vector2.ZERO

var _target: Node2D = null

var active := false
var vy := 0.0
var safe_time := 0.0
var _trail_timer := 0.0
var _difficulty_t := 0.0

@export var scroll_speed := 140.0  # px/s, how fast the “graph” moves
@export var pixel_x := 110.0       # where the dot lives inside the minigame area
@export var trail_width := 2.0

@export var time_to_reach_min_gap := 6.0 # seconds to go from start gap -> min_gap (linear)

@export var materialize_time := 0.35

var _start_upper_h := 0.0
var _start_lower_h := 0.0
var _start_lower_y := 0.0
var _start_gap := 0.0

var _mat_tween: Tween

func _ready() -> void:
	visible = false
	set_process(false)

	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	viewport.size = size

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		viewport.size = size

func start() -> void:
	active = true
	visible = true
	set_process(true)

	hide_message()

	vy = 0.0
	safe_time = 0.0
	_trail_timer = 0.0
	_difficulty_t = 0.0

	_mg_base_pos = mg.position
	_shake_time = 0.0
	_shake_offset = Vector2.ZERO
	mg.position = _mg_base_pos

	trail.width = trail_width
	trail.clear_points()

	pixel.position.x = pixel_x
	var mid_y := mg.size.y * 0.5
	_set_pixel_y(mid_y)

	_start_upper_h = upper.size.y
	_start_lower_h = lower.size.y
	_start_lower_y = lower.position.y
	_start_gap = mg.size.y - _start_upper_h - _start_lower_h

	var mat := output.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("reveal", 1.0)



func stop() -> void:
	active = false
	visible = false
	set_process(false)
	mg.position = _mg_base_pos

func _process(delta: float) -> void:
	_follow_target()

	if not active:
		return

	_difficulty_t += delta
	_update_bounds(delta)

	var up := Input.is_action_pressed("interact")

	# Physics-ish motion
	var ay := gravity
	if up:
		ay -= lift_accel

	vy = clamp(vy + ay * delta, -max_speed, max_speed)

	var y := pixel.position.y + vy * delta
	_set_pixel_y(y)

	_update_trail(delta)

		# Bounds collision check (touching red = bad)
	var top_limit := upper.position.y + upper.size.y
	var bottom_limit := lower.position.y - pixel.size.y

	if pixel.position.y <= top_limit:
		pixel.position.y = top_limit
		vy = 0.0
		emit_signal("failed")
		stop()
		return
	elif pixel.position.y >= bottom_limit:
		pixel.position.y = bottom_limit
		vy = 0.0
		emit_signal("failed")
		stop()
		return

	_apply_shake(delta, top_limit, bottom_limit)

	# "Safe band" for escape progress:
	# safe if you're not too close to either bound
	var safe_top := top_limit + safe_margin
	var safe_bottom := bottom_limit - safe_margin

	if pixel.position.y >= safe_top and pixel.position.y <= safe_bottom:
		safe_time += delta
	else:
		safe_time = max(0.0, safe_time - delta * 0.7)

	if safe_time >= time_in_safe_to_escape:
		emit_signal("escaped")
		stop()

func _set_pixel_y(y: float) -> void:
	# clamp within minigame rect (soft clamp; hard clamp is handled by bounds)
	y = clamp(y, 0.0, mg.size.y - pixel.size.y)
	pixel.position.y = y

func _update_trail(delta: float) -> void:
	_trail_timer += delta
	if _trail_timer < trail_point_every:
		return
	_trail_timer = 0.0

	# 1) scroll existing points left
	var dx := scroll_speed * trail_point_every  # consistent shift per sample
	for i in range(trail.get_point_count()):
		var pt := trail.get_point_position(i)
		pt.x -= dx
		trail.set_point_position(i, pt)

	# 2) add new point at current pixel position (center)
	var p := pixel.position + pixel.size * 0.5
	trail.add_point(p)

	# 3) trim points off the left + limit count
	while trail.get_point_count() > 0 and trail.get_point_position(0).x < 0.0:
		trail.remove_point(0)

	while trail.get_point_count() > trail_max_points:
		trail.remove_point(0)

func _update_bounds(_delta: float) -> void:
	if time_to_reach_min_gap <= 0.0:
		return

	# Compute linear progress 0..1 over the whole minigame duration
	var t: float = clamp(_difficulty_t / time_to_reach_min_gap, 0.0, 1.0)

	# Gap closes linearly from starting gap to min_gap
	var target_gap: float = lerp(_start_gap, min_gap, t)

	# How much total height we need to add to bounds to achieve target gap
	var total_added := (_start_gap - target_gap)
	if total_added < 0.0:
		total_added = 0.0

	# Split evenly between upper and lower
	var add_each: float = total_added * 0.5

	# Upper grows downward
	upper.size.y = _start_upper_h + add_each

	# Lower grows upward: increase height AND move top edge up
	lower.size.y = _start_lower_h + add_each
	lower.position.y = _start_lower_y - add_each

	upper.queue_redraw()
	lower.queue_redraw()


func _follow_target() -> void:
	if _target == null:
		return

	# Convert world -> screen (UI) coordinates using the viewport's canvas transform
	var screen_pos := get_viewport().get_canvas_transform() * _target.global_position

	var desired := screen_pos + head_offset - size * 0.5

	var vp := get_viewport_rect().size
	desired.x = clamp(desired.x, clamp_margin, vp.x - size.x - clamp_margin)
	desired.y = clamp(desired.y, clamp_margin, vp.y - size.y - clamp_margin)

	position = desired

func start_follow(target: Node2D) -> void:
	_target = target
	print("[GrabMinigame] following:", target.name)
	set_process(true)  
	# make sure it's positioned correctly immediately
	_follow_target()

func stop_follow() -> void:
	_target = null

func show_message(text: String, _seconds: float = 0.6) -> void:
	visible = true
	status_label.visible = true
	status_label.text = text

	# make sure follow updates happen immediately
	set_process(true)
	_follow_target()

func hide_message() -> void:
	status_label.visible = false

func _apply_shake(delta: float, top_limit: float, bottom_limit: float) -> void:
	# distance to nearest bound (0 = touching)
	var d_top := pixel.position.y - top_limit
	var d_bot := bottom_limit - pixel.position.y
	var closest: float = min(d_top, d_bot)

	# map closeness -> intensity
	var intensity := 0.0
	if closest < shake_start_dist:
		var t := 1.0 - (closest / shake_start_dist) # 0..1
		intensity = (t * t) * shake_max_px          # ease-in (quadratic)

	# deterministic “noisy” shake using 2 sines (feels like jitter, not drifting)
	_shake_time += delta * shake_freq
	var target := Vector2(
		sin(_shake_time * 1.7),
		cos(_shake_time * 2.3)
	) * intensity

	# smooth so it doesn’t look like teleporting pixels
	_shake_offset = _shake_offset.lerp(target, 1.0 - exp(-shake_smooth * delta))

	mg.position = _mg_base_pos + _shake_offset

func materialize() -> void:
	visible = true
	set_process(true)

	var mat := output.material as ShaderMaterial
	if mat == null:
		return

	mat.set_shader_parameter("reveal", 0.0)

	if _mat_tween:
		_mat_tween.kill()

	_mat_tween = create_tween()
	_mat_tween.tween_property(mat, "shader_parameter/reveal", 1.0, materialize_time)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

	# When reveal finishes, trigger particles
	_mat_tween.finished.connect(_play_pixel_rain)


func play_spawn_fx() -> void:
	materialize()
	_play_pixel_rain()

func _play_pixel_rain() -> void:
	if pixel_rain == null:
		return

	# Spawn along the top edge of the window
	pixel_rain.position = Vector2(size.x * 0.5, size.y)

	var pm := pixel_rain.process_material as ParticleProcessMaterial
	if pm:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		# Extents are HALF-size: (half width, half height, half depth)
		pm.emission_box_extents = Vector3(size.x * 0.5, 1.0, 0.0)

		# Fall down
		pm.direction = Vector3(0.0, 1.0, 0.0)
		pm.gravity = Vector3(0.0, 900.0, 0.0)

	pixel_rain.emitting = false
	pixel_rain.restart()
	pixel_rain.emitting = true
