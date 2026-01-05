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
@export var floor_atlas: Vector2i = Vector2i(16, 0)

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

	# Difficulty curve: 0..1
	var d: float = clamp((float(level - 1) * 0.06) + (float(run - 1) * run_growth), 0.0, 1.0)

	# Size grows with level and run
	var w: int = _odd(base_width + (level - 1) * size_growth_per_level + (run - 1) * 2)
	var h: int = _odd(base_height + (level - 1) * size_growth_per_level + (run - 1) * 2)

	_grid_w = w
	_grid_h = h

	_grid = PackedByteArray()
	_grid.resize(w * h)

	start_cell = Vector2i(0, 0)
	exit_cell = Vector2i(w - 1, h - 1)

	# Main path carving
	var turn_chance: float = lerpf(0.0, 0.65, d)
	_carve_main_path(_grid, w, h, start_cell, exit_cell, turn_chance, rng)

	# Dead ends later
	var branch_density: float = clamp((d - 0.35) / 0.65, 0.0, 1.0)
	if branch_density > 0.0:
		var branch_attempts: int = int(lerpf(0.0, float(w * h) * 0.06, branch_density))
		var max_branch_len: int = int(lerpf(2.0, 10.0, branch_density))
		_add_dead_end_branches(_grid, w, h, branch_attempts, max_branch_len, rng)

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

# ---------------- Core generation ----------------

func _carve_main_path(grid: PackedByteArray, w: int, h: int, start: Vector2i, goal: Vector2i, turn_chance: float, rng: RandomNumberGenerator) -> void:
	var p: Vector2i = start
	_set_floor(grid, p.x, p.y, w)

	var dir: Vector2i = _dir_toward(p, goal, rng)

	var safety: int = 0
	while p != goal and safety < w * h * 10:
		safety += 1

		if rng.randf() < turn_chance:
			dir = _turn_dir(dir, rng)

		if rng.randf() < 0.65:
			dir = _dir_toward(p, goal, rng, dir)

		var next: Vector2i = p + dir
		if not _in_bounds(next, w, h):
			dir = _dir_toward(p, goal, rng)
			continue

		p = next
		_set_floor(grid, p.x, p.y, w)

	_set_floor(grid, goal.x, goal.y, w)

func _add_dead_end_branches(grid: PackedByteArray, w: int, h: int, attempts: int, max_len: int, rng: RandomNumberGenerator) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	for _i in range(attempts):
		var seed: Vector2i = _random_floor_cell(grid, w, h, rng)
		if seed == Vector2i(-1, -1):
			return
		if seed == start_cell or seed == exit_cell:
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
				break

			_set_floor(grid, next.x, next.y, w)
			p = next

			if rng.randf() < 0.30:
				dir = _turn_dir(dir, rng)

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

func _dir_toward(from: Vector2i, to: Vector2i, rng: RandomNumberGenerator, prefer: Vector2i = Vector2i.ZERO) -> Vector2i:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y

	var candidates: Array[Vector2i] = []
	if dx > 0: candidates.append(Vector2i(1, 0))
	if dx < 0: candidates.append(Vector2i(-1, 0))
	if dy > 0: candidates.append(Vector2i(0, 1))
	if dy < 0: candidates.append(Vector2i(0, -1))

	if prefer != Vector2i.ZERO and candidates.has(prefer) and rng.randf() < 0.70:
		return prefer

	if candidates.is_empty():
		var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		return dirs[rng.randi_range(0, 3)]

	return candidates[rng.randi_range(0, candidates.size() - 1)]

func _turn_dir(dir: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	if dir == Vector2i(1,0) or dir == Vector2i(-1,0):
		return Vector2i(0, 1) if rng.randf() < 0.5 else Vector2i(0, -1)
	return Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(-1, 0)

func _random_floor_cell(grid: PackedByteArray, w: int, h: int, rng: RandomNumberGenerator) -> Vector2i:
	for _i in range(50):
		var x: int = rng.randi_range(0, w - 1)
		var y: int = rng.randi_range(0, h - 1)
		if _is_floor(grid, x, y, w):
			return Vector2i(x, y)
	return Vector2i(-1, -1)
