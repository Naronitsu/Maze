# Player.gd
# Tilemap-cell movement + fog-of-war reveal + trail writing.
extends CharacterBody2D

@export var step_time: float = 0.10
@export var maze_path: NodePath            # assign: TileMap/MazeLayer
@export var fog_path: NodePath             # assign: FogOfWar
@export var allow_hold_to_repeat: bool = false

# GameController (trail + path distance utilities)
@export var controller_path: NodePath

# Optional: presence node (only needed if you want set_eyes_closed)
@export var presence_path: NodePath

@export var close_eyes_action: StringName = &"close_eyes"
@export var run_action: StringName = &"run"

# Animation grace: keeps "run" active briefly between tile-steps.
@export var run_grace_time: float = 0.20

# Optional local history (kept for potential UI/debug)
@export var trail_history_max: int = 80

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var maze: MazeLayer = get_node_or_null(maze_path) as MazeLayer
@onready var fog: FogOfWar = get_node_or_null(fog_path) as FogOfWar
@onready var controller: GameController = get_node_or_null(controller_path) as GameController
@onready var presence: Node = (get_node_or_null(presence_path) if presence_path != NodePath() else null)

var cell: Vector2i
var trail_history: Array[Vector2i] = []

var _moving := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0
var _run_grace := 0.0
var _eyes_closed := false

const _DIR_ACTIONS := [
	{ "action": "move_up", "dir": Vector2i(0, -1) },
	{ "action": "move_down", "dir": Vector2i(0, 1) },
	{ "action": "move_left", "dir": Vector2i(-1, 0) },
	{ "action": "move_right", "dir": Vector2i(1, 0) },
]

func _ready() -> void:
	if maze == null:
		push_error("Player: maze_path not set or MazeLayer missing")
		return
	if fog == null:
		push_error("Player: fog_path not set or FogOfWar missing")
		return

	# Determine initial cell robustly.
	if maze.get_world_bounds().size == Vector2.ZERO:
		cell = maze.local_to_map(maze.to_local(global_position))
	else:
		cell = maze.get_spawn_cell()

	global_position = _cell_to_global(cell)

	if controller != null:
		controller.record_player_cell(cell)

	fog.reveal_now()
	_play_anim(&"idle")

func _physics_process(delta: float) -> void:
	_update_eyes_state()
	_update_run_grace(delta)

	if _moving:
		_advance_move(delta)
		return

	_play_anim(&"run" if _run_grace > 0.0 else &"idle")

	var dir := _read_move_dir()
	if dir != Vector2i.ZERO:
		_try_step(dir)

# -----------------------------------------------------------------------------
# Eyes closed mechanic (fog suspend + optional presence hook)
# -----------------------------------------------------------------------------

func _update_eyes_state() -> void:
	var want_closed := Input.is_action_pressed(close_eyes_action)
	if want_closed == _eyes_closed:
		return

	_eyes_closed = want_closed
	if _eyes_closed:
		fog.reset_fog()
		fog.set_suspended(true)
		if presence != null and presence.has_method("set_eyes_closed"):
			presence.call("set_eyes_closed", true)
	else:
		fog.set_suspended(false)
		fog.reveal_now()
		if presence != null and presence.has_method("set_eyes_closed"):
			presence.call("set_eyes_closed", false)

# -----------------------------------------------------------------------------
# Movement
# -----------------------------------------------------------------------------

func _update_run_grace(delta: float) -> void:
	if _run_grace > 0.0:
		_run_grace = maxf(_run_grace - delta, 0.0)

func _advance_move(delta: float) -> void:
	_play_anim(&"run")
	_t += delta / step_time
	if _t >= 1.0:
		_t = 1.0
	global_position = _from.lerp(_to, _t)
	if _t >= 1.0:
		_moving = false
		fog.reveal_now()

func _read_move_dir() -> Vector2i:
	# Priority order is the list order.
	for entry in _DIR_ACTIONS:
		var action: String = entry["action"]
		var d: Vector2i = entry["dir"]
		if allow_hold_to_repeat:
			if Input.is_action_pressed(action):
				return d
		else:
			if Input.is_action_just_pressed(action):
				return d
	return Vector2i.ZERO

func _try_step(dir: Vector2i) -> void:
	var target_cell: Vector2i = cell + dir

	# Block if not walkable.
	if not maze.is_floor(target_cell):
		return

	var target_pos: Vector2 = _cell_to_global(target_cell)

	# Collision safety net.
	var motion := target_pos - global_position
	if move_and_collide(motion, true) != null:
		return

	# Commit step.
	cell = target_cell
	if controller != null:
		controller.record_player_cell(cell)

	trail_history.append(cell)
	if trail_history.size() > trail_history_max:
		trail_history.pop_front()

	_from = global_position
	_to = target_pos
	_t = 0.0
	_moving = true
	_run_grace = run_grace_time

	# Write trail for the monster.
	if controller != null:
		var is_running := Input.is_action_pressed(run_action)
		var amount := controller.trail_add_run if is_running else controller.trail_add_walk
		controller.add_trail_at_world_pos(_to, amount)

func reset_to_cell(new_cell: Vector2i) -> void:
	cell = new_cell
	_moving = false
	_t = 0.0
	_run_grace = 0.0
	global_position = _cell_to_global(cell)
	fog.reveal_now()
	_play_anim(&"idle")

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _cell_to_global(c: Vector2i) -> Vector2:
	return maze.to_global(maze.map_to_local(c))

func _play_anim(name: StringName) -> void:
	if anim == null or anim.sprite_frames == null:
		return
	if not anim.sprite_frames.has_animation(name):
		return
	if anim.animation != name or not anim.is_playing():
		anim.play(name)
