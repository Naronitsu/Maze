extends Node

@export var debug_enabled: bool = true

# --------------------
# TUNING
# --------------------
var attention: float = 0.0        # 0..100
var calm_decay_per_sec: float = 6.0
var spike_on_step: float = 0.8
var spike_on_backtrack: float = 3.0

# "Close eyes" tuning. When eyes are closed, step spikes are reduced and
# attention can be forced down immediately.
@export var eyes_closed_step_multiplier: float = 0.25 # 0..1
@export var attention_drop_on_close: float = 25.0     # 0..100

var _eyes_closed: bool = false

var event_cooldown: float = 0.0
var min_cooldown: float = 0.8
var max_cooldown: float = 2.2

# --------------------
# REFERENCES (set by main scene)
# --------------------
var maze: Node = null
var player: Node = null

# --------------------
# INTERNAL STATE
# --------------------
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_cells: Array[Vector2i] = []

var _last_cell: Vector2i = Vector2i(-999, -999)
var _last_dir: Vector2i = Vector2i.ZERO

# Each entry: {"cell": Vector2i, "time": float}
var _reopen_queue: Array[Dictionary] = []

# --------------------
# LIFECYCLE
# --------------------
func _ready() -> void:
	_rng.randomize()

func setup(p_player: Node, p_maze: Node) -> void:
	player = p_player
	maze = p_maze
	_last_cells.clear()
	_last_cell = Vector2i(-999, -999)
	_last_dir = Vector2i.ZERO
	_reopen_queue.clear()

# --------------------
# PLAYER FEEDBACK
# --------------------
func on_player_step(cell: Vector2i) -> void:
	# Track movement direction
	if _last_cell != Vector2i(-999, -999):
		_last_dir = cell - _last_cell
	_last_cell = cell

	var mult: float = eyes_closed_step_multiplier if _eyes_closed else 1.0
	attention = clamp(attention + (spike_on_step * mult), 0.0, 100.0)

	# Backtracking spike
	if _last_cells.has(cell):
		attention = clamp(attention + (spike_on_backtrack * mult), 0.0, 100.0)

	_last_cells.append(cell)
	if _last_cells.size() > 30:
		_last_cells.pop_front()

	if debug_enabled:
		print("[Presence] step=", cell, " dir=", _last_dir, " attention=", attention)

func set_eyes_closed(v: bool) -> void:
	# Only apply the drop on the transition to closed.
	if v and not _eyes_closed:
		attention = max(attention - attention_drop_on_close, 0.0)
	_eyes_closed = v

# --------------------
# MAIN LOOP
# --------------------
func _process(delta: float) -> void:
	attention = clamp(attention - calm_decay_per_sec * delta, 0.0, 100.0)

	_process_reopen_queue()

	event_cooldown -= delta
	if event_cooldown <= 0.0 and maze != null and player != null:
		_try_fire_event()

# --------------------
# EVENT SELECTION
# --------------------
func _try_fire_event() -> void:
	var a: float = attention / 100.0
	var roll: float = _rng.randf()

	event_cooldown = lerp(max_cooldown, min_cooldown, a)

	if debug_enabled:
		print("[Presence] roll=", roll, " a=", a, " cooldown=", event_cooldown)

	if roll < lerp(0.10, 0.35, a):
		_event_sound_near_player()
	elif roll < lerp(0.16, 0.55, a):
		_event_flicker()
	elif roll < lerp(0.25, 0.80, a):
		_event_close_path_behind()
	# else: silence

# --------------------
# EVENTS
# --------------------
func _event_sound_near_player() -> void:
	if not (player is Node2D):
		return

	var p: Vector2 = (player as Node2D).global_position
	var offset: Vector2 = Vector2(
		_rng.randi_range(-96, 96),
		_rng.randi_range(-96, 96)
	)

	var pos: Vector2 = p + offset

	var scene: Node = get_tree().current_scene
	if scene != null and scene.has_method("play_presence_sound"):
		scene.call("play_presence_sound", pos)

	if debug_enabled:
		print("[Presence] SOUND at ", pos)

func _event_flicker() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.has_method("presence_blackout"):
		scene.call("presence_blackout", 0.55) # seconds

func _event_close_path_behind() -> void:
	if attention < 15.0:
		return
	if maze == null or player == null:
		return

	# Player cell
	var pc_any: Variant = player.get("cell")
	if typeof(pc_any) != TYPE_VECTOR2I:
		return
	var pc: Vector2i = pc_any as Vector2i

	# Exit cell
	var exit_any: Variant = maze.get("exit_cell")
	if typeof(exit_any) != TYPE_VECTOR2I:
		return
	var exit_cell: Vector2i = exit_any as Vector2i

	if _last_dir == Vector2i.ZERO:
		return

	var behind: Vector2i = pc - _last_dir

	var candidates: Array[Vector2i] = [
		behind,
		behind + Vector2i(_last_dir.y, _last_dir.x),
		behind + Vector2i(-_last_dir.y, -_last_dir.x)
	]

	for c: Vector2i in candidates:
		var inb: bool = bool(maze.call("in_bounds", c))
		if not inb:
			continue
		if c == pc or c == exit_cell:
			continue

		# Only close if currently floor
		var was_floor: bool = bool(maze.call("is_floor", c))
		if not was_floor:
			continue

		# Close it
		maze.call("set_wall_cell", c)

		# Keep it fair: must still have a path to exit
		var ok: bool = bool(maze.call("has_path", pc, exit_cell))
		if ok:
			attention = max(attention - 10.0, 0.0)

			# Schedule reopening in a few seconds
			var delay: float = _rng.randf_range(2.5, 6.0)
			_reopen_queue.append({
				"cell": c,
				"time": (Time.get_ticks_msec() / 1000.0) + delay
			})

			if debug_enabled:
				print("[Presence] CLOSED PATH at ", c, " reopen in ", delay)

			return

		# Revert if it breaks solvability
		maze.call("set_floor_cell", c)

func _process_reopen_queue() -> void:
	if maze == null:
		return

	var now: float = Time.get_ticks_msec() / 1000.0

	# Iterate backwards safely using a while loop
	var i: int = _reopen_queue.size() - 1
	while i >= 0:
		var entry: Dictionary = _reopen_queue[i]

		var reopen_time_any: Variant = entry.get("time")
		var cell_any: Variant = entry.get("cell")

		if typeof(reopen_time_any) != TYPE_FLOAT or typeof(cell_any) != TYPE_VECTOR2I:
			_reopen_queue.remove_at(i)
			i -= 1
			continue

		var reopen_time: float = reopen_time_any as float
		var cell: Vector2i = cell_any as Vector2i

		if now >= reopen_time:
			# Reopen if still a wall
			var is_floor_now: bool = bool(maze.call("is_floor", cell))
			if not is_floor_now:
				maze.call("set_floor_cell", cell)
				if debug_enabled:
					print("[Presence] REOPENED PATH at ", cell)

			_reopen_queue.remove_at(i)

		i -= 1
