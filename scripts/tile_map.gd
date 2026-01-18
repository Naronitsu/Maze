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

# ---- FLOOR terrain (set in editor) ----
# terrain_set_id = Terrain Set index that contains your "Floor" terrain
# floor_terrain_id = terrain index inside that set
@export var terrain_set_id: int = 0
@export var floor_terrain_id: int = 0

# ---- Single atlas tiles (NOT in any terrain) ----
# Walls are a single atlas tile
@export var wall_atlas: Vector2i = Vector2i(1, 0)

# Door tile
@export var door_atlas: Vector2i = Vector2i(3, 0)

# ---- Shaping knobs ----
@export var blob_chance_min: float = 0.03
@export var blob_chance_max: float = 0.10
@export var blob_radius_min: int = 1
@export var blob_radius_max: int = 2

@export var enable_thinning: bool = true
@export var thinning_passes_min: int = 0
@export var thinning_passes_max: int = 250

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
	var rng := RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = int(rng_seed + level * 1009 + run * 7919)

	var d: float = clamp((float(level - 1) * 0.06) + (float(run - 1) * run_growth), 0.0, 1.0)

	var w: int = _odd(base_width + (level - 1) * size_growth_per_level + (run - 1) * 2)
	var h: int = _odd(base_height + (level - 1) * size_growth_per_level + (run - 1) * 2)
	_grid_w = w
	_grid_h = h

	_grid = PackedByteArray()
	_grid.resize(w * h) # default walls (0)

	var start_y: int = rng.randi_range(1, h - 2)
	var exit_y: int = rng.randi_range(1, h - 2)
	start_cell = Vector2i(0, start_y)
	exit_cell = Vector2i(w - 1, exit_y)

	var start_in: Vector2i = _step_inside(start_cell, w, h)
	var exit_in: Vector2i = _step_inside(exit_cell, w, h)

	var wiggle: float = lerpf(0.0, 0.55, d)
	_carve_main_path_monotone(_grid, w, h, start_in, exit_in, wiggle, d, rng)

	var branch_density: float = clamp((d - 0.05) / 0.95, 0.0, 1.0)
	var area: float = float(w * h)
	var branch_attempts: int = int(lerpf(area * 0.01, area * 0.06, branch_density))
	var max_branch_len: int = int(lerpf(3.0, 12.0, branch_density))
	var turn_chance: float = lerpf(0.15, 0.55, branch_density)

	if branch_attempts > 0:
		_add_dead_end_branches(_grid, w, h, branch_attempts, max_branch_len, turn_chance, rng)

	_enforce_two_border_doors(_grid, w, h, start_cell, exit_cell)

	if enable_thinning:
		var passes: int = int(lerpf(float(thinning_passes_min), float(thinning_passes_max), d))
		passes = int(float(passes) * clamp(area / 625.0, 0.8, 2.5))
		_thin_floors_preserve_path(_grid, w, h, rng, start_in, exit_in, passes)

	_render_grid(_grid, w, h)

	return {
		"start": start_cell,
		"exit": exit_cell,
		"spawn": get_spawn_cell(), # spawn inside, not on the border door
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

# Entrance should NOT trigger next level; only exit does.
func is_exit_cell(cell: Vector2i) -> bool:
	return cell == exit_cell

func is_entrance_cell(cell: Vector2i) -> bool:
	return cell == start_cell

func get_spawn_cell() -> Vector2i:
	return _step_inside(start_cell, _grid_w, _grid_h)

# ---------------- Rendering (floor autotile) ----------------

func _render_grid(grid: PackedByteArray, w: int, h: int) -> void:
	clear()

	var floor_cells: Array[Vector2i] = []
	var wall_cells: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			if _is_floor(grid, x, y, w):
				floor_cells.append(c)
			else:
				wall_cells.append(c)

	# 1) Autotile FLOOR (terrain)
	_apply_floor_terrain(floor_cells)

	# 2) Paint WALLS as a single atlas tile
	for c in wall_cells:
		set_cell(c, source_id, wall_atlas)

	# 3) Doors last (doors are NOT in terrain)
	_place_doors()

# ---------------- Floor terrain application ----------------

func _apply_floor_terrain(floor_cells: Array[Vector2i]) -> void:
	if floor_cells.is_empty():
		return

	if has_method("set_cells_terrain_connect"):
		set_cells_terrain_connect(floor_cells, terrain_set_id, floor_terrain_id)
	else:
		push_warning("TileMapLayer.set_cells_terrain_connect() not available. Floor autotiling cannot run.")

	update_internals()

func _apply_floor_terrain_local(center: Vector2i, radius: int = 2) -> void:
	var cells: Array[Vector2i] = []
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c):
				continue
			if c == start_cell or c == exit_cell:
				continue
			if _grid[_idx(c.x, c.y, _grid_w)] == 1:
				cells.append(c)

	_apply_floor_terrain(cells)

# ---------------- Doors ----------------

func _place_doors() -> void:
	# Doors must be walkable in the grid
	if in_bounds(start_cell):
		_grid[_idx(start_cell.x, start_cell.y, _grid_w)] = 1
	if in_bounds(exit_cell):
		_grid[_idx(exit_cell.x, exit_cell.y, _grid_w)] = 1

	# Overwrite visuals with door sprite (terrain adjacency remains correct)
	set_cell(start_cell, source_id, door_atlas)
	set_cell(exit_cell, source_id, door_atlas)

# ---------------- Public helpers for runtime edits ----------------

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_w and cell.y < _grid_h

func set_wall_cell(cell: Vector2i) -> void:
	if not in_bounds(cell):
		return
	if cell == start_cell or cell == exit_cell:
		return

	_grid[_idx(cell.x, cell.y, _grid_w)] = 0
	_rebuild_patch(cell, 4)

func set_floor_cell(cell: Vector2i) -> void:
	if not in_bounds(cell):
		return

	_grid[_idx(cell.x, cell.y, _grid_w)] = 1
	_rebuild_patch(cell, 4)

func toggle_cell(cell: Vector2i) -> void:
	if not in_bounds(cell):
		return
	if cell == start_cell or cell == exit_cell:
		return
	var i := _idx(cell.x, cell.y, _grid_w)
	if int(_grid[i]) == 1:
		set_wall_cell(cell)
	else:
		set_floor_cell(cell)

func has_path(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	return _grid_has_path(_grid, _grid_w, _grid_h, from_cell, to_cell)

# ---------------- Guaranteed main path ----------------

func _carve_main_path_monotone(grid: PackedByteArray, w: int, h: int, start: Vector2i, goal: Vector2i, wiggle: float, difficulty: float, rng: RandomNumberGenerator) -> void:
	var p: Vector2i = start
	_set_floor(grid, p.x, p.y, w)

	var blob_chance: float = lerpf(blob_chance_min, blob_chance_max, difficulty)

	while p != goal:
		var dx: int = goal.x - p.x
		var dy: int = goal.y - p.y

		var options: Array[Vector2i] = []
		if dx > 0: options.append(Vector2i(1, 0))
		elif dx < 0: options.append(Vector2i(-1, 0))
		if dy > 0: options.append(Vector2i(0, 1))
		elif dy < 0: options.append(Vector2i(0, -1))

		var step: Vector2i
		if options.size() == 1:
			step = options[0]
		else:
			step = options[rng.randi_range(0, 1)] if rng.randf() < wiggle else options[0]

		var next := p + step
		if not _in_bounds(next, w, h):
			if options.size() == 2:
				var alt := options[1] if step == options[0] else options[0]
				next = p + alt
				if not _in_bounds(next, w, h):
					break
			else:
				break

		p = next
		_set_floor(grid, p.x, p.y, w)

		if rng.randf() < blob_chance:
			var r: int = rng.randi_range(blob_radius_min, blob_radius_max)
			_carve_blob(grid, w, h, p, r)

# ---------------- Dead-end branches ----------------

func _add_dead_end_branches(grid: PackedByteArray, w: int, h: int, attempts: int, max_len: int, turn_chance: float, rng: RandomNumberGenerator) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	var start_in: Vector2i = _step_inside(start_cell, w, h)
	var exit_in: Vector2i = _step_inside(exit_cell, w, h)

	for _i in range(attempts):
		var seed: Vector2i = _random_floor_cell(grid, w, h, rng)
		if seed == Vector2i(-1, -1):
			return

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
				break

			_set_floor(grid, next.x, next.y, w)
			p = next

			if rng.randf() < turn_chance:
				dir = _turn_dir(dir, rng)

# ---------------- Optional shaping: blobs ----------------

func _carve_blob(grid: PackedByteArray, w: int, h: int, center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var p := Vector2i(x, y)
			if not _in_bounds(p, w, h):
				continue
			if abs(x - center.x) + abs(y - center.y) <= radius:
				_set_floor(grid, x, y, w)

# ---------------- Border rule: only entrance/exit touch outside ----------------

func _enforce_two_border_doors(grid: PackedByteArray, w: int, h: int, entrance: Vector2i, exit: Vector2i) -> void:
	for x in range(w):
		_set_wall(grid, x, 0, w)
		_set_wall(grid, x, h - 1, w)
	for y in range(h):
		_set_wall(grid, 0, y, w)
		_set_wall(grid, w - 1, y, w)

	_set_floor(grid, entrance.x, entrance.y, w)
	_set_floor(grid, exit.x, exit.y, w)

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
	for _i in range(120):
		var x: int = rng.randi_range(1, w - 2)
		var y: int = rng.randi_range(1, h - 2)
		if _is_floor(grid, x, y, w):
			return Vector2i(x, y)
	return Vector2i(-1, -1)

# ---------------- Grid BFS ----------------

func _grid_has_path(grid: PackedByteArray, w: int, h: int, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not _in_bounds(from_cell, w, h) or not _in_bounds(to_cell, w, h):
		return false
	if not _is_floor(grid, from_cell.x, from_cell.y, w) or not _is_floor(grid, to_cell.x, to_cell.y, w):
		return false

	var visited := PackedByteArray()
	visited.resize(w * h)

	var q: Array[Vector2i] = []
	q.append(from_cell)
	visited[_idx(from_cell.x, from_cell.y, w)] = 1

	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == to_cell:
			return true

		for d in dirs:
			var n: Vector2i = c + d
			if not _in_bounds(n, w, h):
				continue
			var ni: int = _idx(n.x, n.y, w)
			if visited[ni] == 1:
				continue
			if int(grid[ni]) != 1:
				continue
			visited[ni] = 1
			q.append(n)

	return false

# ---------------- Optional thinning ----------------

func _degree_floor(grid: PackedByteArray, w: int, h: int, p: Vector2i) -> int:
	var deg: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for d: Vector2i in dirs:
		var n: Vector2i = p + d
		if _in_bounds(n, w, h) and _is_floor(grid, n.x, n.y, w):
			deg += 1
	return deg

func _thin_floors_preserve_path(
		grid: PackedByteArray,
		w: int,
		h: int,
		rng: RandomNumberGenerator,
		keep_from: Vector2i,
		keep_to: Vector2i,
		passes: int
	) -> void:
	if passes <= 0:
		return

	for _p in range(passes):
		var x: int = rng.randi_range(1, w - 2)
		var y: int = rng.randi_range(1, h - 2)
		var c: Vector2i = Vector2i(x, y)

		if not _is_floor(grid, x, y, w):
			continue
		if c == keep_from or c == keep_to:
			continue

		if c.distance_to(keep_from) <= 1 or c.distance_to(keep_to) <= 1:
			continue

		if _degree_floor(grid, w, h, c) < 3:
			continue

		_set_wall(grid, x, y, w)

		var ok: bool = _grid_has_path(grid, w, h, keep_from, keep_to)
		if not ok:
			_set_floor(grid, x, y, w)

func get_world_bounds() -> Rect2:
	# Tile size in pixels
	var ts: Vector2 = tile_set.tile_size

	# In TileMapLayer, map_to_local(Vector2i(0,0)) is typically the CENTER of cell (0,0)
	# So the top-left corner of the grid is center - half tile.
	var origin_center: Vector2 = map_to_local(Vector2i(0, 0))
	var top_left_local: Vector2 = origin_center - ts * 0.5

	var size_local: Vector2 = Vector2(_grid_w, _grid_h) * ts

	var top_left_global: Vector2 = to_global(top_left_local)
	return Rect2(top_left_global, size_local)

func _refresh_after_edit(center: Vector2i) -> void:
	# Recompute floor terrain in a local area and redraw walls in that same area
	_apply_floor_terrain_local(center, 2)
	_redraw_walls_local(center, 2)
	_place_doors()
	update_internals()

func _redraw_walls_local(center: Vector2i, radius: int = 2) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c):
				continue
			if c == start_cell or c == exit_cell:
				continue
			var i := _idx(c.x, c.y, _grid_w)
			if _grid[i] == 0:
				set_cell(c, source_id, wall_atlas)

func _rebuild_patch(center: Vector2i, radius: int = 4) -> void:
	# 1) wipe all cells in patch so old terrain info can't linger
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c):
				continue
			erase_cell(c)

	# 2) repaint walls (atlas) and collect floors for terrain
	var floor_cells: Array[Vector2i] = []
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c):
				continue
			if c == start_cell or c == exit_cell:
				continue

			var i := _idx(c.x, c.y, _grid_w)
			if _grid[i] == 0:
				set_cell(c, source_id, wall_atlas)
			else:
				floor_cells.append(c)

	# 3) apply floor terrain over floors in this patch
	if not floor_cells.is_empty() and has_method("set_cells_terrain_connect"):
		set_cells_terrain_connect(floor_cells, terrain_set_id, floor_terrain_id)

	# 4) doors on top
	_place_doors()
	update_internals()
