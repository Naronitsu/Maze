# MazeLayer.gd
extends TileMapLayer
class_name MazeLayer

# ---- Progression / tuning ----
@export var base_width: int = 25
@export var base_height: int = 25
@export var size_growth_per_level: int = 2
@export var run_growth: float = 0.12
@export var rng_seed: int = 0

# ---- TileSet atlas info ----
@export var source_id: int = 0
@export var wall_atlas: Vector2i = Vector2i(52, 0)
@export var floor_atlas: Vector2i = Vector2i(63, 0)

# ---- State ----
var level: int = 1
var run: int = 1

var start_cell: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO

var _grid_w: int = 0
var _grid_h: int = 0
var _grid: PackedByteArray = PackedByteArray()

# ---------------- Public API ----------------

func generate() -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = int(rng_seed + level * 1009 + run * 7919)

	# difficulty 0..1
	var d: float = clamp((float(level - 1) * 0.06) + (float(run - 1) * run_growth), 0.0, 1.0)

	# grow map with level/run
	var w: int = _odd(base_width + (level - 1) * size_growth_per_level + (run - 1) * 2)
	var h: int = _odd(base_height + (level - 1) * size_growth_per_level + (run - 1) * 2)
	_grid_w = w
	_grid_h = h

	_grid = PackedByteArray()
	_grid.resize(w * h) # default walls (0)

	# Doors on border, not corners (clear to player)
	start_cell = Vector2i(0, 1)        # left edge
	exit_cell  = Vector2i(w - 1, h - 2)# right edge

	# Carve the guaranteed main path between the inside-adjacent cells
	var start_in: Vector2i = _step_inside(start_cell, w, h)
	var exit_in: Vector2i = _step_inside(exit_cell, w, h)

	# d=0: almost straight; d=1: curvier
	var wiggle: float = lerpf(0.0, 0.55, d)
	_carve_main_path_monotone(_grid, w, h, start_in, exit_in, wiggle, rng)

	# Add dead ends later
	var branch_density: float = clamp((d - 0.35) / 0.65, 0.0, 1.0)
	if branch_density > 0.0:
		var branch_attempts: int = int(lerpf(0.0, float(w * h) * 0.06, branch_density))
		var max_branch_len: int = int(lerpf(2.0, 10.0, branch_density))
		_add_dead_end_branches(_grid, w, h, branch_attempts, max_branch_len, rng)

	# Border rule: ONLY the entrance/exit touch the outside
	_enforce_two_border_doors(_grid, w, h, start_cell, exit_cell)

	_render_grid(_grid, w, h)

	return {
		"start": start_cell,
		"exit": exit_cell,
		"width": w,
		"height": h,
		"difficulty": d,
		"level": level,
		"run": run
	}

func advance_level() -> Dictionary:
	level += 1
	return generate()

func advance_run() -> Dictionary:
	run += 1
	level = 1
	return generate()

func cell_to_global(cell: Vector2i) -> Vector2:
	return to_global(map_to_local(cell))

func is_floor(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_w or cell.y >= _grid_h:
		return false
	return _grid[_idx(cell.x, cell.y, _grid_w)] == 1

# ---------------- Guaranteed main path ----------------

func _carve_main_path_monotone(grid: PackedByteArray, w: int, h: int, start: Vector2i, goal: Vector2i, wiggle: float, rng: RandomNumberGenerator) -> void:
	# Guarantees reach: every step reduces Manhattan distance.
	# wiggle lets it choose between the two “good” directions more randomly, making curves.

	var p: Vector2i = start
	_set_floor(grid, p.x, p.y, w)

	while p != goal:
		var dx: int = goal.x - p.x
		var dy: int = goal.y - p.y

		var options: Array[Vector2i] = []
		if dx > 0: options.append(Vector2i(1, 0))
		elif dx < 0: options.append(Vector2i(-1, 0))
		if dy > 0: options.append(Vector2i(0, 1))
		elif dy < 0: options.append(Vector2i(0, -1))

		# options will be 1 or 2 dirs that move closer
		var step: Vector2i
		if options.size() == 1:
			step = options[0]
		else:
			# wiggle=0 -> prefer a consistent axis (more straight)
			# wiggle=1 -> very random between axes (more curvy)
			if rng.randf() < wiggle:
				step = options[rng.randi_range(0, 1)]
			else:
				# bias toward horizontal first (gives “line then turn” feel early)
				step = options[0]

		var next: Vector2i = p + step
		# extra safety; should always be in-bounds if start/goal are interior
		if not _in_bounds(next, w, h):
			# fallback: pick the other option if possible
			if options.size() == 2:
				var alt: Vector2i = options[1] if step == options[0] else options[0]
				next = p + alt
				if not _in_bounds(next, w, h):
					break
			else:
				break

		p = next
		_set_floor(grid, p.x, p.y, w)

# ---------------- Dead-end branches ----------------

func _add_dead_end_branches(grid: PackedByteArray, w: int, h: int, attempts: int, max_len: int, rng: RandomNumberGenerator) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	var start_in: Vector2i = _step_inside(start_cell, w, h)
	var exit_in: Vector2i = _step_inside(exit_cell, w, h)

	for _i in range(attempts):
		var seed: Vector2i = _random_floor_cell(grid, w, h, rng)
		if seed == Vector2i(-1, -1):
			return

		# keep entrance/exit corridor clean
		if seed == start_in or seed == exit_in:
			continue

		var wall_dirs: Array[Vector2i] = []
		for d in dirs:
			var n: Vector2i = seed + d
			if _in_bounds(n, w, h) and not _is_floor(grid, n.x, n.y, w):
				wall_dirs.append(d)
		if wall_dirs.is_empty():
			continue

		var dir: Vector2i = wall_dirs[rng.randi_range(0, wall_dirs.size() - 1)]
		var length: int = rng.randi_range(1, max_len)

		var p: Vector2i = seed
		for _k in range(length):
			var next: Vector2i = p + dir
			if not _in_bounds(next, w, h):
				break
			if _is_floor(grid, next.x, next.y, w):
				break # don't reconnect; keep it a dead end

			_set_floor(grid, next.x, next.y, w)
			p = next

			if rng.randf() < 0.30:
				dir = _turn_dir(dir, rng)

# ---------------- Border rule: only entrance/exit touch outside ----------------

func _enforce_two_border_doors(grid: PackedByteArray, w: int, h: int, entrance: Vector2i, exit: Vector2i) -> void:
	# 1) border all walls
	for x in range(w):
		_set_wall(grid, x, 0, w)
		_set_wall(grid, x, h - 1, w)
	for y in range(h):
		_set_wall(grid, 0, y, w)
		_set_wall(grid, w - 1, y, w)

	# 2) exactly two border floors (doors)
	_set_floor(grid, entrance.x, entrance.y, w)
	_set_floor(grid, exit.x, exit.y, w)

	# 3) connect doors to interior
	var e_in: Vector2i = _step_inside(entrance, w, h)
	var x_in: Vector2i = _step_inside(exit, w, h)
	_set_floor(grid, e_in.x, e_in.y, w)
	_set_floor(grid, x_in.x, x_in.y, w)

func _step_inside(p: Vector2i, w: int, h: int) -> Vector2i:
	if p.x == 0: return Vector2i(1, p.y)
	if p.x == w - 1: return Vector2i(w - 2, p.y)
	if p.y == 0: return Vector2i(p.x, 1)
	return Vector2i(p.x, h - 2)

func _set_wall(grid: PackedByteArray, x: int, y: int, w: int) -> void:
	grid[_idx(x, y, w)] = 0

# ---------------- Rendering ----------------

func _render_grid(grid: PackedByteArray, w: int, h: int) -> void:
	clear()
	for y in range(h):
		for x in range(w):
			var floor_here: bool = _is_floor(grid, x, y, w)
			set_cell(Vector2i(x, y), source_id, floor_atlas if floor_here else wall_atlas)

# ---------------- Helpers ----------------

func _odd(n: int) -> int:
	return n if (n % 2) == 1 else n + 1

func _idx(x: int, y: int, w: int) -> int:
	return y * w + x

func _in_bounds(p: Vector2i, w: int, h: int) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

func _is_floor(grid: PackedByteArray, x: int, y: int, w: int) -> bool:
	return grid[_idx(x, y, w)] == 1

func _set_floor(grid: PackedByteArray, x: int, y: int, w: int) -> void:
	grid[_idx(x, y, w)] = 1

func _turn_dir(dir: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	if dir == Vector2i(1,0) or dir == Vector2i(-1,0):
		return Vector2i(0, 1) if rng.randf() < 0.5 else Vector2i(0, -1)
	return Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(-1, 0)

func _random_floor_cell(grid: PackedByteArray, w: int, h: int, rng: RandomNumberGenerator) -> Vector2i:
	for _i in range(100):
		var x: int = rng.randi_range(1, w - 2) # interior only
		var y: int = rng.randi_range(1, h - 2)
		if _is_floor(grid, x, y, w):
			return Vector2i(x, y)
	return Vector2i(-1, -1)
