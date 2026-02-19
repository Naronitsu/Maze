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
@export var bounds_shrink_speed := 18.0   # px/s PER BOUND (gap closes at ~2x this)
@export var min_gap := 90.0               # minimum allowed gap between bounds (px)
@export var shrink_ramp := 0.0            # 0 = constant speed, >0 ramps up (per second)

var _target: Node2D = null

var active := false
var vy := 0.0
var safe_time := 0.0
var _trail_timer := 0.0
var _difficulty_t := 0.0

@onready var mg: Control = $minigame
@onready var pixel: Control = $minigame/pixel
@onready var upper: Control = $minigame/upperBound
@onready var lower: Control = $minigame/lowerBound
@onready var trail: Line2D = $minigame/trail

@onready var status_label: Label = $Panel/StatusLabel

@export var scroll_speed := 140.0  # px/s, how fast the “graph” moves
@export var pixel_x := 110.0       # where the dot lives inside the minigame area
@export var trail_width := 2.0

func start() -> void:
	active = true
	visible = true
	set_process(true)

	hide_message()

	vy = 0.0
	safe_time = 0.0
	_trail_timer = 0.0
	_difficulty_t = 0.0

	trail.width = trail_width
	trail.clear_points()

	pixel.position.x = pixel_x
	var mid_y := mg.size.y * 0.5
	_set_pixel_y(mid_y)


func stop() -> void:
	active = false
	visible = false
	set_process(false)

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

func _update_bounds(delta: float) -> void:
	# inner edges of the bounds (in minigame local space)
	var upper_inner := upper.position.y + upper.size.y   # lower edge of upper bound
	var lower_inner := lower.position.y                  # upper edge of lower bound

	var gap := lower_inner - upper_inner
	if gap <= min_gap:
		return

	# shrink speed, optionally ramping with time
	var ramp := 1.0 + _difficulty_t * shrink_ramp
	var step := bounds_shrink_speed * ramp * delta

	# prevent overshooting min_gap (each bound scales by step, so gap shrinks by 2*step)
	var max_step := (gap - min_gap) * 0.5
	step = min(step, max_step)

	# Scale the y size of both bounds (increase height)
	upper.size.y += step
	lower.size.y += step

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
	# make sure it's positioned correctly immediately
	_follow_target()

func stop_follow() -> void:
	_target = null

func show_message(text: String, _seconds: float = 0.6) -> void:
	visible = true
	status_label.visible = true
	status_label.text = text
	# optional: you can animate/fade here

func hide_message() -> void:
	status_label.visible = false
