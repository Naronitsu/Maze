# MazeLayer.gd
extends TileMapLayer
class_name DungeonMazeLayer

signal door_opened(cell: Vector2i)
signal door_closed(cell: Vector2i)

# ---- Progression / tuning ----
@export var base_width: int = 25
@export var base_height: int = 25
@export var size_growth_per_level: int = 2
@export var run_growth: float = 0.12
@export var rng_seed: int = 12345

# Optional cap behavior for advance_run()
@export var runs_per_level: int = 0 # 0 = never shows level progression, just increments run

# ---- TileSet atlas info ----
@export var source_id: int = 0

# ---- FLOOR terrain (set in editor) ----
@export var terrain_set_id: int = 0
@export var floor_terrain_id: int = 0

# ---- Single atlas tiles (NOT in any terrain) ----
@export var wall_atlas: Vector2i = Vector2i(1, 0)

# Doors (NOT in terrain) - these MUST be non-colliding tiles
@export var door_open_atlas: Vector2i = Vector2i(3, 7)
@export var door_closed_atlas: Vector2i = Vector2i(4, 7)

# ---- Constants ----
const DIR4: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const INVALID: Vector2i = Vector2i(-999999, -999999)

# ---- State ----
var level: int = 1
var run: int = 1

var start_cell: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO

var _grid_w: int = 0
var _grid_h: int = 0

# 0 = wall, 1 = floor
var _grid: PackedByteArray = PackedByteArray()

# 0 = not room, 1 = room tile (used to prevent overlaps + corridor thickening rules)
var _room_mask: PackedByteArray = PackedByteArray()

# Doors (visual overlay; doors do NOT change walkability)
var _doors_open: Array[Vector2i] = []
var _doors_closed: Array[Vector2i] = []

# 1 = closed door at this cell, 0 = not closed
var _door_closed_mask: PackedByteArray = PackedByteArray()

# --------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------

func set_level_and_run(p_level: int, p_run: int) -> void:
	level = max(1, p_level)
	run = max(1, p_run)

func build() -> void:
	generate()

func generate() -> Dictionary:
	return generate_with_retries(12)

func _generate_once() -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = int(rng_seed + level * 1009 + run * 7919)

	var raw: float = clamp((float(level - 1) * 0.06) + (float(run - 1) * run_growth), 0.0, 1.0)
	var difficulty: float = pow(raw, 0.65)

	var w: int = _odd(base_width + (level - 1) * size_growth_per_level + (run - 1) * 2)
	var h: int = _odd(base_height + (level - 1) * size_growth_per_level + (run - 1) * 2)
	_grid_w = w
	_grid_h = h

	_door_closed_mask = PackedByteArray()
	_door_closed_mask.resize(w * h) # defaults to 0

	_grid = PackedByteArray()
	_grid.resize(w * h) # defaults to 0 (walls)

	_room_mask = PackedByteArray()
	_room_mask.resize(w * h) # defaults to 0

	_doors_open.clear()
	_doors_closed.clear()

	# Entrance/Exit are always on the left/right border.
	var start_y: int = rng.randi_range(1, h - 2)
	var exit_y: int = rng.randi_range(1, h - 2)
	if difficulty < 0.12:
		exit_y = start_y

	start_cell = Vector2i(0, start_y)
	exit_cell = Vector2i(w - 1, exit_y)

	var start_in: Vector2i = _step_inside(start_cell, w, h)
	var exit_in: Vector2i = _step_inside(exit_cell, w, h)

	_enforce_two_border_doors_and_floors(_grid, w, h, start_cell, exit_cell)

	# --- Main corridor spine (rectilinear; width-1 enforced) ---
	var spine: Array[Vector2i] = []
	if difficulty < 0.12:
		spine = _carve_corridor_path(_grid, w, h, start_in, exit_in, rng, false)
	else:
		var waypoint_count: int = roundi(lerpf(0.0, 4.0, difficulty))
		var waypoints: Array[Vector2i] = []
		for i: int in range(waypoint_count):
			waypoints.append(Vector2i(rng.randi_range(2, w - 3), rng.randi_range(1, h - 2)))
		waypoints.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)

		var p: Vector2i = start_in
		for wp: Vector2i in waypoints:
			spine.append_array(_carve_corridor_path(_grid, w, h, p, wp, rng, true))
			p = wp
		spine.append_array(_carve_corridor_path(_grid, w, h, p, exit_in, rng, true))

	_set_corridor_floor(start_in, w)
	_set_corridor_floor(exit_in, w)

	# --- Rooms ---
	var area: int = w * h
	var rooms_target: int = roundi(lerpf(0.0, clamp(float(area) / 260.0, 2.0, 10.0), difficulty))
	rooms_target = clamp(rooms_target, 0, 12)

	var carved_rooms: int = 0
	var max_room_attempts: int = rooms_target * 18

	for _i: int in range(max_room_attempts):
		if carved_rooms >= rooms_target:
			break
		if spine.is_empty():
			break

		var anchor: Vector2i = spine[rng.randi_range(0, spine.size() - 1)]

		var rw: int = rng.randi_range(5, clamp(roundi(lerpf(7.0, 11.0, difficulty)), 7, 13))
		var rh: int = rng.randi_range(5, clamp(roundi(lerpf(7.0, 11.0, difficulty)), 7, 13))
		rw = _odd(rw)
		rh = _odd(rh)

		var offset: Vector2i = Vector2i(rng.randi_range(-rw, rw), rng.randi_range(-rh, rh))
		var center: Vector2i = anchor + offset

		var half_rw: int = rw >> 1
		var half_rh: int = rh >> 1
		var top_left: Vector2i = Vector2i(center.x - half_rw, center.y - half_rh)
		var rect: Rect2i = Rect2i(top_left, Vector2i(rw, rh))

		if not _rect_in_bounds(rect, w, h, 1):
			continue
		if _rect_touches_border(rect, w, h, 1):
			continue
		if _rect_overlaps_rooms(rect, w, 1):
			continue

		# Reject rooms that would swallow the corridor anchor (prevents failed door direction).
		if rect.has_point(anchor):
			continue

		_carve_room_rect(rect, w)

		var pick: Dictionary = _pick_room_edge_and_door_outside(anchor, rect)
		var room_edge: Vector2i = pick["room_edge"]
		var door_outside: Vector2i = pick["door_outside"]

		if not _in_bounds(door_outside.x, door_outside.y, w, h):
			_fill_rect_walls(rect, w)
			continue
		if _is_room(door_outside, w):
			_fill_rect_walls(rect, w)
			continue

		# Carve corridor to outside doorway tile. Final tile may touch exactly the chosen room edge.
		var path_to_door: Array[Vector2i] = _carve_corridor_path(_grid, w, h, anchor, door_outside, rng, true, room_edge)
		if path_to_door.is_empty() or path_to_door[path_to_door.size() - 1] != door_outside:
			_fill_rect_walls(rect, w)
			continue

		# IMPORTANT: do NOT place doors here. We'll auto-place doors by adjacency scan.
		carved_rooms += 1

	# --- Branch corridors / dead ends ---
	var branch_density: float = clamp((difficulty - 0.10) / 0.90, 0.0, 1.0)
	var branches_target: int = clamp(roundi(lerpf(0.0, clamp(float(area) / 150.0, 1.0, 14.0), branch_density)), 0, 18)

	for _b: int in range(branches_target):
		if spine.is_empty():
			break

		var start_branch: Vector2i = spine[rng.randi_range(0, spine.size() - 1)]
		var dirs: Array[Vector2i] = DIR4.duplicate()
		dirs.shuffle()

		var dir: Vector2i = Vector2i.ZERO
		for d0: Vector2i in dirs:
			var n: Vector2i = start_branch + d0
			if _in_bounds(n.x, n.y, w, h) and not _is_floor(_grid, n.x, n.y, w):
				dir = d0
				break
		if dir == Vector2i.ZERO:
			continue

		var max_branch_len: int = clamp(roundi(lerpf(3.0, 10.0, branch_density)), 3, 12)
		var branch_len: int = rng.randi_range(3, max_branch_len)

		var cur: Vector2i = start_branch
		var first: Vector2i = cur + dir
		if not _can_carve_corridor_cell(first, dir, w, h, false, INVALID):
			continue

		for _j: int in range(branch_len):
			var nxt: Vector2i = cur + dir
			if not _in_bounds(nxt.x, nxt.y, w, h):
				break
			if not _can_carve_corridor_cell(nxt, dir, w, h, false, INVALID):
				break
			_set_corridor_floor(nxt, w)
			cur = nxt

	# Rebuild doors:
	#  - keep border doors (entrance/exit)
	#  - add open doors on corridor tiles adjacent to rooms
	_rebuild_room_doors()

	_render_grid()

	return {
		"w": w,
		"h": h,
		"start_cell": start_cell,
		"exit_cell": exit_cell,
		"doors_open": _doors_open,
		"doors_closed": _doors_closed
	}


# --------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------

func _render_grid() -> void:
	clear()

	# Floors via terrain
	var floor_cells: Array[Vector2i] = []
	for y: int in range(_grid_h):
		for x: int in range(_grid_w):
			if _is_floor(_grid, x, y, _grid_w):
				floor_cells.append(Vector2i(x, y))
	if not floor_cells.is_empty():
		set_cells_terrain_connect(floor_cells, terrain_set_id, floor_terrain_id, true)

	# Walls via atlas
	for y: int in range(_grid_h):
		for x: int in range(_grid_w):
			if not _is_floor(_grid, x, y, _grid_w):
				set_cell(Vector2i(x, y), source_id, wall_atlas, 0)

	_place_doors()

func _place_doors() -> void:
	for c: Vector2i in _doors_open:
		if _in_bounds(c.x, c.y, _grid_w, _grid_h):
			_set_door_closed(c, false)
			set_cell(c, source_id, door_open_atlas, 0)
	for c: Vector2i in _doors_closed:
		if _in_bounds(c.x, c.y, _grid_w, _grid_h):
			_set_door_closed(c, true)
			set_cell(c, source_id, door_closed_atlas, 0)


# --------------------------------------------------------------------
# Grid helpers
# --------------------------------------------------------------------

func _idx(x: int, y: int, w: int) -> int:
	return y * w + x

func _in_bounds(x: int, y: int, w: int, h: int) -> bool:
	return x >= 0 and x < w and y >= 0 and y < h

func _is_floor(grid: PackedByteArray, x: int, y: int, w: int) -> bool:
	return grid[_idx(x, y, w)] == 1

func _set_floor(grid: PackedByteArray, x: int, y: int, w: int) -> void:
	grid[_idx(x, y, w)] = 1

func _is_room(c: Vector2i, w: int) -> bool:
	return _room_mask[_idx(c.x, c.y, w)] == 1

func _set_room(c: Vector2i, w: int) -> void:
	_room_mask[_idx(c.x, c.y, w)] = 1

func _is_corridor_floor(c: Vector2i, w: int) -> bool:
	return _grid[_idx(c.x, c.y, w)] == 1 and _room_mask[_idx(c.x, c.y, w)] == 0

func _set_corridor_floor(c: Vector2i, w: int) -> void:
	_grid[_idx(c.x, c.y, w)] = 1
	_room_mask[_idx(c.x, c.y, w)] = 0


# --------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------

func _odd(v: int) -> int:
	return v | 1

func _rect_in_bounds(rect: Rect2i, w: int, h: int, pad: int) -> bool:
	return rect.position.x >= pad and rect.position.y >= pad and rect.end.x <= (w - pad) and rect.end.y <= (h - pad)

func _rect_touches_border(rect: Rect2i, w: int, h: int, pad: int) -> bool:
	return rect.position.x <= pad or rect.position.y <= pad or rect.end.x >= (w - pad) or rect.end.y >= (h - pad)

func _rect_overlaps_rooms(rect: Rect2i, w: int, buffer: int) -> bool:
	var expanded: Rect2i = rect.grow(buffer)
	for y: int in range(expanded.position.y, expanded.end.y):
		for x: int in range(expanded.position.x, expanded.end.x):
			if _in_bounds(x, y, _grid_w, _grid_h) and _room_mask[_idx(x, y, w)] == 1:
				return true
	return false

func _fill_rect_walls(rect: Rect2i, w: int) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if _in_bounds(x, y, _grid_w, _grid_h):
				_grid[_idx(x, y, w)] = 0
				_room_mask[_idx(x, y, w)] = 0

func _carve_room_rect(rect: Rect2i, w: int) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			_set_floor(_grid, x, y, w)
			_set_room(Vector2i(x, y), w)

func _step_inside(border_cell: Vector2i, w: int, h: int) -> Vector2i:
	if border_cell.x == 0:
		return Vector2i(1, border_cell.y)
	if border_cell.x == w - 1:
		return Vector2i(w - 2, border_cell.y)
	if border_cell.y == 0:
		return Vector2i(border_cell.x, 1)
	return Vector2i(border_cell.x, h - 2)


# --------------------------------------------------------------------
# Border doors + floors
# --------------------------------------------------------------------

func _add_open_door(cell: Vector2i) -> void:
	if not _doors_open.has(cell):
		_doors_open.append(cell)
	# Ensure logic agrees with visuals
	if _door_closed_mask.size() > 0:
		_door_closed_mask[_idx(cell.x, cell.y, _grid_w)] = 0

func _add_closed_door(cell: Vector2i) -> void:
	if not _doors_closed.has(cell):
		_doors_closed.append(cell)
	_set_door_closed(cell, true)

func _enforce_two_border_doors_and_floors(grid: PackedByteArray, w: int, h: int, start: Vector2i, exit: Vector2i) -> void:
	var s_in := _step_inside(start, w, h)
	var e_in := _step_inside(exit, w, h)

	# Make both border and inside tiles walkable.
	_set_floor(grid, start.x, start.y, w)
	_set_floor(grid, exit.x, exit.y, w)
	_set_floor(grid, s_in.x, s_in.y, w)
	_set_floor(grid, e_in.x, e_in.y, w)

	# Keep your existing progression logic: doors on the border cells.
	_add_open_door(start)
	_add_open_door(exit)

func is_door_closed(cell: Vector2i) -> bool:
	if _grid_w <= 0 or _grid_h <= 0:
		return false
	if not _in_bounds(cell.x, cell.y, _grid_w, _grid_h):
		return false
	return _door_closed_mask[_idx(cell.x, cell.y, _grid_w)] == 1

func _set_door_closed(cell: Vector2i, closed: bool) -> void:
	if not _in_bounds(cell.x, cell.y, _grid_w, _grid_h):
		return
	_door_closed_mask[_idx(cell.x, cell.y, _grid_w)] = 1 if closed else 0

func try_open_door_at(cell: Vector2i) -> bool:
	if not is_door_closed(cell):
		return false

	_set_door_closed(cell, false)
	_doors_closed.erase(cell)
	if not _doors_open.has(cell):
		_doors_open.append(cell)

	set_cell(cell, source_id, door_open_atlas, 0)

	emit_signal("door_opened", cell)
	return true
	
func is_door_open(cell: Vector2i) -> bool:
	# "Open" means it's in doors_open (and not closed in the mask)
	return _doors_open.has(cell) and not is_door_closed(cell)

func is_door_cell(cell: Vector2i) -> bool:
	return is_door_closed(cell) or _doors_open.has(cell)

func try_close_door_at(cell: Vector2i) -> bool:
	if not _doors_open.has(cell):
		return false
	if is_door_closed(cell):
		return false

	# Optional: prevent closing border doors
	if cell.x == 0 or cell.x == _grid_w - 1 or cell.y == 0 or cell.y == _grid_h - 1:
		return false

	_set_door_closed(cell, true)
	_doors_open.erase(cell)
	if not _doors_closed.has(cell):
		_doors_closed.append(cell)

	set_cell(cell, source_id, door_closed_atlas, 0)

	emit_signal("door_closed", cell)
	return true

func toggle_door_at(cell: Vector2i) -> bool:
	if is_door_closed(cell):
		return try_open_door_at(cell)
	return try_close_door_at(cell)

# --------------------------------------------------------------------
# Room doorway selection
# --------------------------------------------------------------------

func _pick_room_edge_and_door_outside(anchor: Vector2i, rect: Rect2i) -> Dictionary:
	var best_edge: Vector2i = rect.position
	var best_dist: int = 1 << 30

	for x: int in range(rect.position.x, rect.end.x):
		var t: Vector2i = Vector2i(x, rect.position.y)
		var b: Vector2i = Vector2i(x, rect.end.y - 1)
		var dt: int = abs(anchor.x - t.x) + abs(anchor.y - t.y)
		var db: int = abs(anchor.x - b.x) + abs(anchor.y - b.y)
		if dt < best_dist:
			best_dist = dt
			best_edge = t
		if db < best_dist:
			best_dist = db
			best_edge = b

	for y: int in range(rect.position.y, rect.end.y):
		var l: Vector2i = Vector2i(rect.position.x, y)
		var r: Vector2i = Vector2i(rect.end.x - 1, y)
		var dl: int = abs(anchor.x - l.x) + abs(anchor.y - l.y)
		var dr: int = abs(anchor.x - r.x) + abs(anchor.y - r.y)
		if dl < best_dist:
			best_dist = dl
			best_edge = l
		if dr < best_dist:
			best_dist = dr
			best_edge = r

	var out_dir: Vector2i = _cardinal_dir_towards(best_edge, anchor)
	var door_outside: Vector2i = best_edge + out_dir

	return {"room_edge": best_edge, "door_outside": door_outside}

func _cardinal_dir_towards(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var dx: int = to_cell.x - from_cell.x
	var dy: int = to_cell.y - from_cell.y
	if abs(dx) > abs(dy):
		return Vector2i(signi(dx), 0)
	return Vector2i(0, signi(dy))


# --------------------------------------------------------------------
# Corridor carving
# --------------------------------------------------------------------

func _carve_corridor_path(
	grid: PackedByteArray,
	w: int,
	h: int,
	a: Vector2i,
	b: Vector2i,
	rng: RandomNumberGenerator,
	allow_bend: bool,
	required_room_neighbor: Vector2i = INVALID
) -> Array[Vector2i]:

	var carved: Array[Vector2i] = []
	if a == b:
		return carved

	var horiz_first: bool = true
	if allow_bend:
		horiz_first = rng.randi() % 2 == 0

	var mid: Vector2i = (Vector2i(b.x, a.y) if horiz_first else Vector2i(a.x, b.y))

	carved.append_array(_carve_line_corridor(grid, w, h, a, mid))
	carved.append_array(_carve_line_corridor(grid, w, h, mid, b, required_room_neighbor))
	return carved

func _carve_line_corridor(
	p_grid_unused: PackedByteArray,
	w: int,
	h: int,
	a: Vector2i,
	b: Vector2i,
	required_room_neighbor: Vector2i = INVALID
) -> Array[Vector2i]:

	var carved: Array[Vector2i] = []
	if a.x != b.x and a.y != b.y:
		return carved

	var dx: int = signi(b.x - a.x)
	var dy: int = signi(b.y - a.y)
	var dir: Vector2i = Vector2i(dx, dy)
	var p: Vector2i = a

	while p != b:
		var nxt: Vector2i = Vector2i(p.x + dx, p.y + dy)
		if not _in_bounds(nxt.x, nxt.y, w, h):
			break

		# Allow routing over existing corridor floor tiles.
		if _is_corridor_floor(nxt, w):
			carved.append(nxt)
			p = nxt
			continue

		var is_final: bool = (nxt == b)
		var allow_room_touch: bool = is_final and (required_room_neighbor != INVALID)

		if not _can_carve_corridor_cell(nxt, dir, w, h, allow_room_touch, required_room_neighbor):
			break

		_set_corridor_floor(nxt, w)
		carved.append(nxt)
		p = nxt

	return carved

func _can_carve_corridor_cell(
	c: Vector2i,
	dir: Vector2i,
	w: int,
	h: int,
	allow_room_touch: bool,
	required_room_neighbor: Vector2i
) -> bool:

	if not _in_bounds(c.x, c.y, w, h):
		return false
	if _is_room(c, w):
		return false
	if _is_corridor_floor(c, w):
		return false

	var side_dirs: Array[Vector2i] = []

	if dir.x != 0:
		side_dirs.append(Vector2i.UP)
		side_dirs.append(Vector2i.DOWN)
	else:
		side_dirs.append(Vector2i.LEFT)
		side_dirs.append(Vector2i.RIGHT)

	# Prevent 2-wide corridors
	for sd: Vector2i in side_dirs:
		var n: Vector2i = c + sd
		if _in_bounds(n.x, n.y, w, h) and _is_corridor_floor(n, w):
			return false

	# Prevent corridors hugging room walls, unless final doorway tile
	for sd: Vector2i in side_dirs:
		var n2: Vector2i = c + sd
		if not _in_bounds(n2.x, n2.y, w, h):
			continue
		if _is_room(n2, w) and not allow_room_touch:
			return false

	# If final tile is allowed to touch room: exactly 1 room neighbor, must be required_room_neighbor
	if allow_room_touch:
		var room_neighbors: int = 0
		var matches_required: bool = false
		for d: Vector2i in DIR4:
			var n3: Vector2i = c + d
			if _in_bounds(n3.x, n3.y, w, h) and _is_room(n3, w):
				room_neighbors += 1
				if n3 == required_room_neighbor:
					matches_required = true
		if room_neighbors != 1:
			return false
		if not matches_required:
			return false

	return true


# --------------------------------------------------------------------
# Door rebuild: corridor-adjacent-to-room => door on corridor tile
# --------------------------------------------------------------------

func _rebuild_room_doors() -> void:
	# Keep only border doors already added (entrance/exit).
	var keep_open: Array[Vector2i] = []
	for d in _doors_open:
		if d.x == 0 or d.x == _grid_w - 1 or d.y == 0 or d.y == _grid_h - 1:
			keep_open.append(d)
	_doors_open = keep_open

	# Rebuild closed doors from scratch
	_doors_closed.clear()
	# (Mask will be set in _place_doors, but we can also clear it here)
	for i in range(_door_closed_mask.size()):
		_door_closed_mask[i] = 0

	for y in range(_grid_h):
		for x in range(_grid_w):
			var c := Vector2i(x, y)

			if not _is_corridor_floor(c, _grid_w):
				continue

			# Skip borders; entrance/exit handled separately
			if x == 0 or x == _grid_w - 1 or y == 0 or y == _grid_h - 1:
				continue

			var room_neighbors := 0
			var corridor_neighbors := 0

			for d in DIR4:
				var n := c + d
				if not _in_bounds(n.x, n.y, _grid_w, _grid_h):
					continue
				if _is_room(n, _grid_w):
					room_neighbors += 1
				elif _is_corridor_floor(n, _grid_w):
					corridor_neighbors += 1

			# Door rule:
			# - exactly one room neighbor (a single room connection)
			# - at least one corridor neighbor (connected)
			if room_neighbors == 1 and corridor_neighbors >= 1:
				_add_closed_door(c)

# --------------------------------------------------------------------
# Compatibility helpers for your existing game/player scripts
# --------------------------------------------------------------------
func get_world_bounds() -> Rect2:
	# Bounds of the generated grid in WORLD coordinates, aligned to tile edges.
	# Works by taking the world-space center of (0,0) and (w-1,h-1),
	# then expanding by half a cell in each direction.

	if _grid_w <= 0 or _grid_h <= 0:
		return Rect2()

	var tl_cell := Vector2i(0, 0)
	var br_cell := Vector2i(_grid_w - 1, _grid_h - 1)

	var tl_center := to_global(map_to_local(tl_cell))
	var br_center := to_global(map_to_local(br_cell))

	# Cell size in local space; use TileMapLayer's tile_set tile size if available.
	var ts := tile_set
	var cell_size := Vector2(32, 32)
	if ts != null:
		cell_size = Vector2(ts.tile_size)

	# Expand from centers to edges
	var min_x :float= min(tl_center.x, br_center.x) - cell_size.x * 0.5
	var min_y :float= min(tl_center.y, br_center.y) - cell_size.y * 0.5
	var max_x :float= max(tl_center.x, br_center.x) + cell_size.x * 0.5
	var max_y :float= max(tl_center.y, br_center.y) + cell_size.y * 0.5

	# Include the full width/height across all tiles
	max_x += cell_size.x * float(_grid_w - 1) * 0.0 # (kept explicit; centers already account for br_cell)
	max_y += cell_size.y * float(_grid_h - 1) * 0.0

	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func get_spawn_cell() -> Vector2i:
	# Your game can spawn just inside the entrance...
	return _step_inside(start_cell, _grid_w, _grid_h)

func get_exit_cell() -> Vector2i:
	# ...but progression logic can still use the border exit_cell if it wants.
	return _step_inside(exit_cell, _grid_w, _grid_h)

func is_floor(cell: Vector2i) -> bool:
	if _grid_w <= 0 or _grid_h <= 0:
		return false
	if not _in_bounds(cell.x, cell.y, _grid_w, _grid_h):
		return false

	# Closed doors block movement.
	if is_door_closed(cell):
		return false

	return _grid[_idx(cell.x, cell.y, _grid_w)] == 1

func is_wall(cell: Vector2i) -> bool:
	return not is_floor(cell)

func advance_run() -> Dictionary:
	run += 1
	if runs_per_level > 0 and run > runs_per_level:
		run = 1
		level += 1
	return generate()

func generate_with_retries(max_attempts: int = 12) -> Dictionary:
	for i in range(max_attempts):
		var data := _generate_once()
		if _has_path_from_start_to_exit():
			_render_grid()
			return data
	# last attempt (shows something rather than nothing)
	_render_grid()
	return {
		"w": _grid_w,
		"h": _grid_h,
		"start_cell": start_cell,
		"exit_cell": exit_cell,
		"doors_open": _doors_open,
		"doors_closed": _doors_closed
	}
	
func _has_path_from_start_to_exit() -> bool:
	var s := _step_inside(start_cell, _grid_w, _grid_h)
	var e := _step_inside(exit_cell, _grid_w, _grid_h)

	if not is_floor(s) or not is_floor(e):
		return false

	var visited := PackedByteArray()
	visited.resize(_grid_w * _grid_h)

	var q: Array[Vector2i] = [s]
	visited[_idx(s.x, s.y, _grid_w)] = 1

	while not q.is_empty():
		var c : Vector2i = q.pop_front()
		if c == e:
			return true
		for d in DIR4:
			var n := c + d
			if not _in_bounds(n.x, n.y, _grid_w, _grid_h):
				continue
			var ii := _idx(n.x, n.y, _grid_w)
			if visited[ii] == 1:
				continue
			if not is_floor(n):
				continue
			visited[ii] = 1
			q.append(n)

	return false
