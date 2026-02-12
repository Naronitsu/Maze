# MazeLayer.gd
# 
# REFACTORED: Now generates into a GridModel first, then renders to TileMap.
# All public APIs preserved for backward compatibility.
# Access the logical model via get_grid_model() if needed.
#
extends TileMapLayer
class_name DungeonMazeLayer

# Rooms-first generation outputs (cell-space Rect2i).
var _reward_room_rect: Rect2i = Rect2i()
var _minor_room_rects: Array[Rect2i] = []

signal door_opened(cell: Vector2i)
signal door_closed(cell: Vector2i)

# ---- Progression / tuning ----
@export var base_width: int = 31
@export var base_height: int = 31
@export var size_growth_per_level: int = 2
@export var run_growth: float = 0.12
@export var rng_seed: int = 12345

# Optional cap behavior for advance_run()
@export var runs_per_level: int = 0 # 0 = never shows level progression, just increments run

# ---- Debug ----
@export var debug_dump_on_fail: bool = false

# Validate room layout + connectivity in debug builds.
@export var debug_validate: bool = true

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

# NEW: Logical grid model (generation happens here first)
var _grid_model: GridModel = null

# LEGACY: Maintained for backward compatibility and internal rendering
# 0 = wall, 1 = floor
var _grid: PackedByteArray = PackedByteArray()

# 0 = not room, 1 = room tile (used to prevent overlaps + corridor thickening rules)
var _room_mask: PackedByteArray = PackedByteArray()

# 1 = generation is not allowed to carve this cell (used to protect room doorways)
var _no_carve_mask: PackedByteArray = PackedByteArray()

# Doors (visual overlay; doors do NOT change walkability)
var _doors_open: Array[Vector2i] = []
var _doors_closed: Array[Vector2i] = []

# 1 = closed door at this cell, 0 = not closed
var _door_closed_mask: PackedByteArray = PackedByteArray()

# --------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------

## Get the logical grid model (optional; for advanced queries)
## Returns null if generation hasn't run yet.
func get_grid_model() -> GridModel:
	return _grid_model

## Debug helper: Verify GridModel matches legacy PackedByteArray representation
## Returns true if they match, false otherwise. Prints mismatches if found.
func _verify_grid_model_sync() -> bool:
	if _grid_model == null:
		return true  # Nothing to verify yet
	
	var mismatches: int = 0
	for y in range(_grid_h):
		for x in range(_grid_w):
			var legacy_is_floor: bool = (_grid[_idx(x, y, _grid_w)] == 1)
			var model_is_floor: bool = _grid_model.is_floor(x, y)
			
			if legacy_is_floor != model_is_floor:
				mismatches += 1
				if mismatches <= 10:  # Limit output
					print("[GridModel Mismatch] at (%d,%d): legacy=%s, model=%s" % [x, y, legacy_is_floor, model_is_floor])
	
	if mismatches > 0:
		push_warning("[GridModel] Found %d mismatches between legacy grid and GridModel" % mismatches)
		return false
	return true

func set_level_and_run(p_level: int, p_run: int) -> void:
	level = max(1, p_level)
	run = max(1, p_run)

func build() -> void:
	generate()

func generate() -> Dictionary:
	return generate_with_retries(12)


func _shuffle_in_place(arr: Array, rng: RandomNumberGenerator) -> void:
	# Deterministic Fisher–Yates shuffle using the provided RNG.
	# IMPORTANT: Godot's Array.shuffle() uses the global RNG, which breaks seeded generation.
	var n := arr.size()
	if n <= 1:
		return
	for i: int in range(n - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _generate_once() -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = int(rng_seed + level * 1009 + run * 7919)

	# Difficulty curve: start easier on level 1 and ramp up gradually.
	# raw in [0,1] then exponent skews early levels lower.
	var raw: float = clamp(0.08 + (float(level - 1) * 0.045) + (float(run - 1) * run_growth), 0.0, 1.0)
	var difficulty: float = pow(raw, 0.85)

	var w: int = _odd(base_width + (level - 1) * size_growth_per_level + (run - 1) * 2)
	var h: int = _odd(base_height + (level - 1) * size_growth_per_level + (run - 1) * 2)
	_grid_w = w
	_grid_h = h

	# Initialize GridModel
	_grid_model = GridModel.new(w, h)

	# Initialize legacy arrays (kept in sync for backward compatibility)
	_door_closed_mask = PackedByteArray()
	_door_closed_mask.resize(w * h) # defaults to 0

	_grid = PackedByteArray()
	_grid.resize(w * h) # defaults to 0 (walls)

	_room_mask = PackedByteArray()
	_room_mask.resize(w * h) # defaults to 0

	_no_carve_mask = PackedByteArray()
	_no_carve_mask.resize(w * h) # defaults to 0

	_doors_open.clear()
	_doors_closed.clear()

	# Entrance/Exit are always on the left/right border.
	var start_y: int = rng.randi_range(1, h - 2)
	var exit_y: int = rng.randi_range(1, h - 2)
	if difficulty < 0.04:
		exit_y = start_y

	start_cell = Vector2i(0, start_y)
	exit_cell = Vector2i(w - 1, exit_y)

	var start_in: Vector2i = _step_inside(start_cell, w, h)
	var exit_in: Vector2i = _step_inside(exit_cell, w, h)

	_enforce_two_border_doors_and_floors(_grid, w, h, start_cell, exit_cell)

	# ----------------------------------------------------------------
	# Rooms-first generation
	# ----------------------------------------------------------------
	var area: int = w * h

	# --- 1) Place fixed rooms on solid grid (guaranteed) ---
	var reward_rect: Rect2i = _place_reward_room(rng, w, h, start_in)
	_carve_room_rect_kind(reward_rect, w, GridModel.RoomKind.REWARD)

	var minor_rects: Array[Rect2i] = _place_minor_rooms(rng, w, h, 3)
	for r: Rect2i in minor_rects:
		_carve_room_rect_kind(r, w, GridModel.RoomKind.MINOR)

	# Store room rects for other systems (pillars, spawn strategies, etc.)
	_reward_room_rect = reward_rect
	_minor_room_rects = minor_rects.duplicate()

	# --- 2) Pick door candidates (marks only; actual doors are rebuilt later) ---
	# We pick a slightly larger pool so we can retry if some candidates can't be connected cleanly.
	var reward_doors_pool: Array[Dictionary] = _pick_room_doors(rng, reward_rect, 8, w, h)
	var minor_doors_pool: Array[Dictionary] = []
	for r2: Rect2i in minor_rects:
		minor_doors_pool.append_array(_pick_room_doors(rng, r2, 4, w, h))

	# --- 3) Carve the main maze spine FIRST (keeps start->exit playable without opening room doors) ---
	# This is the original stable corridor carve, but it must now route around pre-placed rooms.
	var spine: Array[Vector2i] = []
	if difficulty < 0.04:
		spine = _carve_corridor_path(_grid, w, h, start_in, exit_in, rng, false)
	else:
		var waypoint_count: int = roundi(lerpf(1.0, 6.0, difficulty))
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
	# If rooms block the strict carve, force a safe connection.
	if spine.is_empty() or spine[spine.size() - 1] != exit_in:
		_force_connect_points_safe(start_in, exit_in, w, h)

	# Gather anchors for room connections and branching.
	var anchors: Array[Vector2i] = _gather_corridor_cells(w, h)
	if anchors.is_empty():
		anchors.append(start_in)

	# --- 4) Connect rooms as side branches off the spine network ---
	# Reward room: connect 2-3 doors.
	var reward_wanted: int = clampi(rng.randi_range(2, 3), 2, 3)
	_connect_doors_to_network(reward_doors_pool, reward_wanted, anchors, rng, w, h)

	# Minor rooms: connect at least 3 doors total.
	_connect_doors_to_network(minor_doors_pool, 3, anchors, rng, w, h)

	# --- 5) Add branching corridors / dead ends (original behavior) ---
	var branch_density: float = clamp((difficulty - 0.05) / 0.95, 0.0, 1.0)
	var base_branches: float = clamp(float(area) / 200.0, 2.0, 8.0)
	var difficulty_multiplier: float = 1.0 + (branch_density * 2.5)
	var branches_target: int = clamp(roundi(base_branches * difficulty_multiplier), 6, 40)

	for _b: int in range(branches_target):
		if anchors.is_empty():
			break

		var start_branch: Vector2i = anchors[rng.randi_range(0, anchors.size() - 1)]
		# Never branch from doorway tiles (keeps room entrances as clean 1-tile stubs).
		if _is_doorway_corridor_cell(start_branch, w):
			continue
		var dirs: Array[Vector2i] = DIR4.duplicate()
		_shuffle_in_place(dirs, rng)

		var dir: Vector2i = Vector2i.ZERO
		for d0: Vector2i in dirs:
			var n: Vector2i = start_branch + d0
			if _in_bounds(n.x, n.y, w, h) and not _is_floor(_grid, n.x, n.y, w):
				dir = d0
				break
		if dir == Vector2i.ZERO:
			continue

		var min_branch_len: int = clamp(roundi(lerpf(2.0, 4.0, branch_density)), 2, 4)
		var max_branch_len: int = clamp(roundi(lerpf(4.0, 14.0, branch_density)), 4, 14)
		var branch_len: int = rng.randi_range(min_branch_len, max_branch_len)

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

	# --- 6) Ensure all rooms are reachable (strict 1-wide, door-friendly) ---
	_ensure_all_rooms_reachable(reward_rect, minor_rects, anchors, rng, w, h)

	# --- 7) Increase complexity on remaining space ---
	_carve_maze_fill(rng, w, h, difficulty)

	# Rebuild doors:
	#  - keep border doors (entrance/exit)
	#  - add open doors on corridor tiles adjacent to rooms
	_rebuild_room_doors()

	# Optional debug validation
	if debug_validate and OS.is_debug_build():
		_debug_validate_rooms_and_connectivity(reward_rect, minor_rects)

	_render_grid()

	# Debug verification that GridModel matches legacy arrays
	if OS.is_debug_build() and debug_dump_on_fail:
		if not _verify_grid_model_sync():
			push_warning("[MazeGen] GridModel sync check failed!")

	return {
		"w": w,
		"h": h,
		"start_cell": start_cell,
		"exit_cell": exit_cell,
		"doors_open": _doors_open,
		"doors_closed": _doors_closed
	}


func get_room_rects() -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	if _reward_room_rect.size != Vector2i.ZERO:
		result.append(_reward_room_rect)
	result.append_array(_minor_room_rects)
	return result

func get_reward_room_rect() -> Rect2i:
	return _reward_room_rect

func get_minor_room_rects() -> Array[Rect2i]:
	return _minor_room_rects.duplicate()


# --------------------------------------------------------------------
# Rooms-first helpers
# --------------------------------------------------------------------

func _carve_room_rect_kind(rect: Rect2i, w: int, kind: GridModel.RoomKind) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			_set_floor(_grid, x, y, w)
			_set_room(Vector2i(x, y), w)
			if _grid_model != null:
				_grid_model.set_room_kind(x, y, kind)


func _place_reward_room(rng: RandomNumberGenerator, w: int, h: int, start_in: Vector2i) -> Rect2i:
	# Reward room: exactly 7x7, padded from border >=2 and not too close to the entrance.
	var size := Vector2i(7, 7)
	var half := Vector2i(3, 3)
	var pad := 2
	var min_dist: int = max(8, (w + h) / 6)

	var attempts := 400
	for _i in range(attempts):
		var cx := rng.randi_range(pad + half.x, (w - pad - 1) - half.x)
		var cy := rng.randi_range(pad + half.y, (h - pad - 1) - half.y)
		var center := Vector2i(cx, cy)
		if (abs(center.x - start_in.x) + abs(center.y - start_in.y)) < min_dist:
			continue
		var rect := Rect2i(center - half, size)
		if not _rect_in_bounds(rect, w, h, pad):
			continue
		if _rect_overlaps_rooms(rect, w, 2):
			continue
		return rect

	# Fallback: deterministic-ish placement near center.
	var fallback_center := Vector2i(w / 2, h / 2)
	return Rect2i(fallback_center - half, size)


func _place_minor_rooms(rng: RandomNumberGenerator, w: int, h: int, count: int) -> Array[Rect2i]:
	# Minor rooms: exactly 5x5, non-overlapping, spacing >=2 preferred.
	var result: Array[Rect2i] = []
	var size := Vector2i(5, 5)
	var half := Vector2i(2, 2)
	var pad := 2
	var spacing := 2

	# Try strict spacing first, then relax to guarantee placement.
	for relax in range(3):
		var local_spacing: int = max(0, spacing - relax)
		var attempts := 1200
		while attempts > 0 and result.size() < count:
			attempts -= 1
			var cx := rng.randi_range(pad + half.x, (w - pad - 1) - half.x)
			var cy := rng.randi_range(pad + half.y, (h - pad - 1) - half.y)
			var rect := Rect2i(Vector2i(cx, cy) - half, size)
			if not _rect_in_bounds(rect, w, h, pad):
				continue
			if _rect_overlaps_rooms(rect, w, local_spacing):
				continue
			# Also avoid overlaps with minors we haven't carved yet
			var overlap := false
			for r in result:
				if r.grow(local_spacing).intersects(rect):
					overlap = true
					break
			if overlap:
				continue
			# Reserve by writing room mask now (so later placements see it)
			# We reserve with _set_room only (no floor) and immediately clear after selection.
			# This avoids messing with painting while still using _rect_overlaps_rooms.
			result.append(rect)
			# Mark in room mask for subsequent checks
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					_room_mask[_idx(x, y, w)] = 1
		if result.size() >= count:
			break

	# Clear the temporary reservations (rooms will be carved properly right after)
	for r in result:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_room_mask[_idx(x, y, w)] = 0

	return result


func _pick_room_doors(rng: RandomNumberGenerator, rect: Rect2i, door_count: int, w: int, h: int) -> Array[Dictionary]:
	# Returns [{edge: Vector2i, outside: Vector2i}] and marks door candidates on GridModel.
	var doors: Array[Dictionary] = []
	var tries := door_count * 20
	while doors.size() < door_count and tries > 0:
		tries -= 1
		var side := rng.randi_range(0, 3) # 0=top,1=bottom,2=left,3=right
		var edge := Vector2i.ZERO
		var outside := Vector2i.ZERO
		match side:
			0:
				edge = Vector2i(rng.randi_range(rect.position.x + 1, rect.end.x - 2), rect.position.y)
				outside = edge + Vector2i.UP
			1:
				edge = Vector2i(rng.randi_range(rect.position.x + 1, rect.end.x - 2), rect.end.y - 1)
				outside = edge + Vector2i.DOWN
			2:
				edge = Vector2i(rect.position.x, rng.randi_range(rect.position.y + 1, rect.end.y - 2))
				outside = edge + Vector2i.LEFT
			3:
				edge = Vector2i(rect.end.x - 1, rng.randi_range(rect.position.y + 1, rect.end.y - 2))
				outside = edge + Vector2i.RIGHT

		if not _in_bounds(outside.x, outside.y, w, h):
			continue
		# Outside tile must start as solid (avoids connecting into an existing corridor and losing the doorway).
		if _is_floor(_grid, outside.x, outside.y, w):
			continue
		if _is_room(outside, w):
			continue
		# Avoid duplicates
		var dup := false
		for d in doors:
			if d["edge"] == edge:
				dup = true
				break
		if dup:
			continue
		# Mark door candidate on room edge floor cell
		if _grid_model != null:
			_grid_model.set_door_mark(edge.x, edge.y, true)
		doors.append({"edge": edge, "outside": outside})

	return doors


func _ensure_all_rooms_reachable(
	reward_rect: Rect2i,
	minor_rects: Array[Rect2i],
	anchors: Array[Vector2i],
	rng: RandomNumberGenerator,
	w: int,
	h: int
) -> void:
	# Flood-fill from spawn and force-connect any room whose center isn't reachable.
	var spawn := _step_inside(start_cell, w, h)
	var visited: PackedByteArray = _flood_fill_generation_passable(spawn, w, h)
	var reachable_anchors: Array[Vector2i] = _gather_reachable_corridor_cells(visited, w, h)
	if reachable_anchors.is_empty():
		reachable_anchors.append(spawn)

	# Keep the caller's anchors list in sync (helps later systems if they reuse it).
	anchors.clear()
	anchors.append_array(reachable_anchors)

	# Reward room
	if not _is_cell_reachable(visited, reward_rect.position + Vector2i(3, 3), w):
		if _force_connect_room_rect(reward_rect, reachable_anchors, rng, w, h):
			visited = _flood_fill_generation_passable(spawn, w, h)
			reachable_anchors = _gather_reachable_corridor_cells(visited, w, h)

	# Minor rooms
	for r: Rect2i in minor_rects:
		if _is_cell_reachable(visited, r.position + Vector2i(1, 1), w):
			continue
		if _force_connect_room_rect(r, reachable_anchors, rng, w, h):
			visited = _flood_fill_generation_passable(spawn, w, h)
			reachable_anchors = _gather_reachable_corridor_cells(visited, w, h)

	anchors.clear()
	anchors.append_array(reachable_anchors)


func _flood_fill_generation_passable(start: Vector2i, w: int, h: int) -> PackedByteArray:
	var visited := PackedByteArray()
	visited.resize(w * h)
	if not _in_bounds(start.x, start.y, w, h):
		return visited
	if not _is_passable_for_generation(start):
		return visited

	var q: Array[Vector2i] = [start]
	visited[_idx(start.x, start.y, w)] = 1
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in DIR4:
			var n := c + d
			if not _in_bounds(n.x, n.y, w, h):
				continue
			var ii := _idx(n.x, n.y, w)
			if visited[ii] == 1:
				continue
			if not _is_passable_for_generation(n):
				continue
			visited[ii] = 1
			q.append(n)
	return visited


func _is_cell_reachable(visited: PackedByteArray, c: Vector2i, w: int) -> bool:
	if not _in_bounds(c.x, c.y, _grid_w, _grid_h):
		return false
	return visited[_idx(c.x, c.y, w)] == 1


func _gather_reachable_corridor_cells(visited: PackedByteArray, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(h):
		for x: int in range(w):
			if visited[_idx(x, y, w)] != 1:
				continue
			var c := Vector2i(x, y)
			if _is_corridor_floor(c, w):
				out.append(c)
	return out


func _force_connect_room_rect(rect: Rect2i, anchors: Array[Vector2i], rng: RandomNumberGenerator, w: int, h: int) -> bool:
	# Attempt to connect the room by carving to an "approach" tile one step beyond
	# the door outside, then carving the final doorway tile (outside) as a dead-end.
	var candidates: Array[Dictionary] = _enumerate_room_door_candidates(rect, w, h, rng)
	if candidates.is_empty():
		return false

	# Rank by distance from approach to nearest anchor.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := 999999
		var db := 999999
		for an: Vector2i in anchors:
			da = min(da, abs(an.x - a["approach"].x) + abs(an.y - a["approach"].y))
			db = min(db, abs(an.x - b["approach"].x) + abs(an.y - b["approach"].y))
		return da < db
	)

	for cand: Dictionary in candidates:
		var edge: Vector2i = cand["edge"]
		var outside: Vector2i = cand["outside"]
		var approach: Vector2i = cand["approach"]
		var step_dir: Vector2i = cand["step_dir"] # approach -> outside

		# Approach may already be corridor floor; that's fine.
		if _is_room(approach, w):
			continue

		var anchor_candidates: Array[Vector2i] = _rank_anchor_candidates(approach, anchors, rng, 0)
		for anchor: Vector2i in anchor_candidates:
			if anchor == approach:
				continue
			var ok_to_approach := _carve_thin_path_bfs(anchor, approach, w, h)
			if not ok_to_approach:
				continue

			# Carve the final doorway tile (outside) from the approach direction.
			if _is_corridor_floor(outside, w):
				return true
			if _is_room(outside, w):
				continue
			if not _in_bounds(outside.x, outside.y, w, h):
				continue
			if not _can_carve_corridor_cell(outside, step_dir, w, h, true, edge):
				continue
			_set_corridor_floor(outside, w)
			_protect_doorway(outside, edge, w, h)
			return true

	return false


func _enumerate_room_door_candidates(rect: Rect2i, w: int, h: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	# Enumerate non-corner edge tiles and their outside/approach tiles.
	# Each candidate returns: {edge, outside, approach, step_dir}
	var out: Array[Dictionary] = []

	# Top / Bottom edges (skip corners)
	for x: int in range(rect.position.x + 1, rect.end.x - 1):
		var top_edge := Vector2i(x, rect.position.y)
		var top_out := top_edge + Vector2i.UP
		_append_door_candidate(out, top_edge, top_out, w, h)
		var bot_edge := Vector2i(x, rect.end.y - 1)
		var bot_out := bot_edge + Vector2i.DOWN
		_append_door_candidate(out, bot_edge, bot_out, w, h)

	# Left / Right edges (skip corners)
	for y: int in range(rect.position.y + 1, rect.end.y - 1):
		var left_edge := Vector2i(rect.position.x, y)
		var left_out := left_edge + Vector2i.LEFT
		_append_door_candidate(out, left_edge, left_out, w, h)
		var right_edge := Vector2i(rect.end.x - 1, y)
		var right_out := right_edge + Vector2i.RIGHT
		_append_door_candidate(out, right_edge, right_out, w, h)

	# Shuffle slightly so ties don't always pick the same side (deterministically).
	_shuffle_in_place(out, rng)
	return out


func _append_door_candidate(dst: Array[Dictionary], edge: Vector2i, outside: Vector2i, w: int, h: int) -> void:
	if not _in_bounds(outside.x, outside.y, w, h):
		return
	if _is_room(outside, w):
		return
	# Outside must be wall at time of selection (keeps the "doorway tile" clean).
	if _is_floor(_grid, outside.x, outside.y, w):
		return

	var outside_dir: Vector2i = outside - edge
	var approach: Vector2i = outside + outside_dir
	if not _in_bounds(approach.x, approach.y, w, h):
		return
	if _is_room(approach, w):
		return

	var step_dir: Vector2i = outside - approach
	dst.append({"edge": edge, "outside": outside, "approach": approach, "step_dir": step_dir})


func _connect_doors_to_network(
	doors_pool: Array[Dictionary],
	wanted_count: int,
	anchors: Array[Vector2i],
	rng: RandomNumberGenerator,
	w: int,
	h: int
) -> void:
	# Attempts to connect up to wanted_count doors as 1-wide corridors into the existing network.
	# Prefers strict carving; falls back to thin BFS that still respects the same rules.
	var used_edges: Dictionary = {}
	var connected := 0

	# Sort pool by (rough) distance to network to reduce failures.
	var pool := doors_pool.duplicate()
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := 999999
		var db := 999999
		for an: Vector2i in anchors:
			da = min(da, abs(an.x - a["outside"].x) + abs(an.y - a["outside"].y))
			db = min(db, abs(an.x - b["outside"].x) + abs(an.y - b["outside"].y))
		return da < db
	)

	for pass_i in range(3):
		if connected >= wanted_count:
			return
		for d: Dictionary in pool:
			if connected >= wanted_count:
				return
			var edge: Vector2i = d["edge"]
			var out: Vector2i = d["outside"]
			if used_edges.has(edge):
				continue
			# Don't connect if the outside is already carved.
			if _is_floor(_grid, out.x, out.y, w):
				continue
			if _is_room(out, w):
				continue

			var anchor_candidates: Array[Vector2i] = _rank_anchor_candidates(out, anchors, rng, pass_i)
			for anchor: Vector2i in anchor_candidates:
				# Enforce perpendicular 1-tile doorway:
				#   anchor -> approach (BFS)
				#   approach -> out (single final carve touching the room edge)
				var room_dir: Vector2i = edge - out # from doorway corridor tile -> room tile
				var away_dir: Vector2i = -room_dir
				var approach: Vector2i = out + away_dir
				if not _in_bounds(approach.x, approach.y, w, h):
					continue
				if _is_room(approach, w):
					continue
				if anchor == approach:
					continue

				var ok := _carve_thin_path_bfs(anchor, approach, w, h)
				if ok:
					# Final doorway step; use direction approach->out (= room_dir)
					if not _is_corridor_floor(out, w):
						ok = _can_carve_corridor_cell(out, room_dir, w, h, true, edge)
						if ok:
							_set_corridor_floor(out, w)
				if ok:
					used_edges[edge] = true
					connected += 1
					_protect_doorway(out, edge, w, h)
					# Add the approach tile as an anchor; never anchor off the doorway tile.
					anchors.append(approach)
					break
				# else: try next anchor


func _rank_anchor_candidates(target: Vector2i, anchors: Array[Vector2i], rng: RandomNumberGenerator, preference_index: int) -> Array[Vector2i]:
	# preference_index 0: nearest-first; later passes include some far/random choices.
	var ranked := anchors.duplicate()
	ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (abs(a.x - target.x) + abs(a.y - target.y)) < (abs(b.x - target.x) + abs(b.y - target.y))
	)
	if ranked.is_empty():
		return ranked

	# Keep a small list for performance.
	var out: Array[Vector2i] = []
	var take_near: int = min(10, ranked.size())
	for i in range(take_near):
		out.append(ranked[i])

	if preference_index >= 1 and ranked.size() > 1:
		# Add a couple of far anchors to encourage loops.
		out.append(ranked[ranked.size() - 1])
		out.append(ranked[max(0, ranked.size() - 2)])
		# Add a few random anchors.
		for _k in range(3):
			out.append(ranked[rng.randi_range(0, ranked.size() - 1)])

	return out


func _carve_maze_fill(rng: RandomNumberGenerator, w: int, h: int, difficulty: float) -> void:
	# Randomized Prim-style maze carve on remaining wall space.
	# Respects existing floors/rooms and avoids hugging rooms.
	var want_loops := difficulty > 0.35
	var carved_between_budget := clampi(int((w * h) / 6), 80, 900)

	# Helper to find nearest odd coordinate near a seed
	var nearest_odd = func(p: Vector2i) -> Vector2i:
		var ox := p.x | 1
		var oy := p.y | 1
		return Vector2i(clampi(ox, 1, w - 2), clampi(oy, 1, h - 2))

	var seeds: Array[Vector2i] = []
	seeds.append(nearest_odd.call(_step_inside(start_cell, w, h)))
	seeds.append(nearest_odd.call(_step_inside(exit_cell, w, h)))

	var frontier: Array[Dictionary] = []
	var frontier_seen := PackedByteArray()
	frontier_seen.resize(w * h)

	var add_frontier = func(from_node: Vector2i) -> void:
		for d in DIR4:
			var to_node := from_node + d * 2
			if not _in_bounds(to_node.x, to_node.y, w, h):
				continue
			if _is_room(to_node, w):
				continue
			# Only consider nodes in the interior
			if to_node.x <= 0 or to_node.x >= w - 1 or to_node.y <= 0 or to_node.y >= h - 1:
				continue
			var key := _idx(to_node.x, to_node.y, w)
			if frontier_seen[key] == 1:
				continue
			frontier_seen[key] = 1
			frontier.append({"from": from_node, "to": to_node, "dir": d})

	var total_between := 0
	for s in seeds:
		if not _in_bounds(s.x, s.y, w, h):
			continue
		if _is_room(s, w):
			continue
		# Ensure seed node is corridor floor
		if not _is_floor(_grid, s.x, s.y, w):
			_set_corridor_floor(s, w)
		add_frontier.call(s)

		while not frontier.is_empty() and total_between < carved_between_budget:
			var pick_i := rng.randi_range(0, frontier.size() - 1)
			var e: Dictionary = frontier[pick_i]
			frontier.remove_at(pick_i)

			var from_node: Vector2i = e["from"]
			var to_node: Vector2i = e["to"]
			var dir: Vector2i = e["dir"]
			var between := from_node + dir

			# Always validate the between cell carving.
			if not _can_carve_corridor_cell(between, dir, w, h, false, INVALID):
				continue
			# Avoid creating tiny 3x3 loop artifacts (a single wall "pillar" enclosed by corridors).
			if _would_enclose_single_wall_pillar(between, w, h):
				continue

			var to_is_floor := _is_floor(_grid, to_node.x, to_node.y, w)
			# Do not connect into already-open nodes unless we're explicitly allowing loops.
			if to_is_floor and not want_loops:
				continue
			if not to_is_floor:
				if not _can_carve_corridor_cell(to_node, dir, w, h, false, INVALID):
					continue
				if _would_enclose_single_wall_pillar(to_node, w, h):
					continue

			# Carve between and (if needed) the node
			_set_corridor_floor(between, w)
			total_between += 1
			if not to_is_floor:
				_set_corridor_floor(to_node, w)
				add_frontier.call(to_node)
			elif want_loops:
				# Loop connection: still expand frontier from the already-open node occasionally
				if rng.randf() < 0.15:
					add_frontier.call(to_node)

	# Extra: sprinkle a few short branches off existing corridors
	var sprinkle := clampi(int(lerpf(4.0, 20.0, difficulty)), 4, 30)
	for _k in range(sprinkle):
		var p := Vector2i(rng.randi_range(1, w - 2), rng.randi_range(1, h - 2))
		if not _is_corridor_floor(p, w):
			continue
		var dirs := DIR4.duplicate()
		_shuffle_in_place(dirs, rng)
		var dir0: Vector2i = dirs[0]
		var nxt := p + dir0
		if _in_bounds(nxt.x, nxt.y, w, h) and _can_carve_corridor_cell(nxt, dir0, w, h, false, INVALID) and not _would_enclose_single_wall_pillar(nxt, w, h):
			_set_corridor_floor(nxt, w)


func _would_enclose_single_wall_pillar(carve_cell: Vector2i, w: int, h: int) -> bool:
	# Detect the common "3x3 ring" artifact: a single wall tile with all 4 cardinal neighbors carved.
	# We conservatively reject any carve that would cause ANY adjacent wall tile to become enclosed.
	for d in DIR4:
		var wall_cell := carve_cell + d
		if not _in_bounds(wall_cell.x, wall_cell.y, w, h):
			continue
		if _is_room(wall_cell, w):
			continue
		if _is_floor(_grid, wall_cell.x, wall_cell.y, w):
			continue # not a wall pillar

		var corridor_neighbors := 0
		for d2 in DIR4:
			var n := wall_cell + d2
			if not _in_bounds(n.x, n.y, w, h):
				continue
			if n == carve_cell:
				corridor_neighbors += 1
			elif _is_corridor_floor(n, w):
				corridor_neighbors += 1
		if corridor_neighbors >= 4:
			return true

	return false


func _gather_corridor_cells(w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(h):
		for x: int in range(w):
			var c := Vector2i(x, y)
			if _is_corridor_floor(c, w):
				out.append(c)
	return out


func _pick_anchor_for_room_door(door_outside: Vector2i, anchors: Array[Vector2i], rng: RandomNumberGenerator, preference_index: int) -> Vector2i:
	# preference_index: 0 = nearest, 1+ = try to bias toward farther anchors (creates variety/loops)
	if anchors.is_empty():
		return door_outside
	var best := anchors[0]
	var best_d := 1 << 30
	var worst := anchors[0]
	var worst_d := -1
	for a: Vector2i in anchors:
		var d: int = abs(a.x - door_outside.x) + abs(a.y - door_outside.y)
		if d < best_d:
			best_d = d
			best = a
		if d > worst_d:
			worst_d = d
			worst = a

	if preference_index <= 0:
		return best
	# 60% far anchor, 40% nearest.
	return (worst if rng.randf() < 0.60 else best)


func _debug_validate_rooms_and_connectivity(reward_rect: Rect2i, minor_rects: Array[Rect2i]) -> void:
	# Reward room checks
	if reward_rect.size != Vector2i(7, 7):
		push_error("[MazeGen] Reward room is not 7x7: %s" % [reward_rect.size])
	assert(reward_rect.size == Vector2i(7, 7))

	# Minor room checks
	assert(minor_rects.size() >= 3)
	for r in minor_rects:
		assert(r.size == Vector2i(5, 5))

	# All room tiles are floors
	for y in range(reward_rect.position.y, reward_rect.end.y):
		for x in range(reward_rect.position.x, reward_rect.end.x):
			assert(_is_floor(_grid, x, y, _grid_w))
	for r2 in minor_rects:
		for y2 in range(r2.position.y, r2.end.y):
			for x2 in range(r2.position.x, r2.end.x):
				assert(_is_floor(_grid, x2, y2, _grid_w))

	# Connectivity: flood fill from spawn (generation-passable)
	var s := _step_inside(start_cell, _grid_w, _grid_h)
	var visited := PackedByteArray()
	visited.resize(_grid_w * _grid_h)
	var q: Array[Vector2i] = [s]
	visited[_idx(s.x, s.y, _grid_w)] = 1
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in DIR4:
			var n := c + d
			if not _in_bounds(n.x, n.y, _grid_w, _grid_h):
				continue
			var ii := _idx(n.x, n.y, _grid_w)
			if visited[ii] == 1:
				continue
			if not _is_passable_for_generation(n):
				continue
			visited[ii] = 1
			q.append(n)

	# Ensure at least one tile in each room is reachable
	var reward_center := reward_rect.position + Vector2i(3, 3)
	assert(visited[_idx(reward_center.x, reward_center.y, _grid_w)] == 1)
	for r3 in minor_rects:
		var cc := r3.position + Vector2i(2, 2)
		assert(visited[_idx(cc.x, cc.y, _grid_w)] == 1)


func _has_path_between(a: Vector2i, b: Vector2i, max_nodes: int = 20000) -> bool:
	if a == b:
		return true
	if not _in_bounds(a.x, a.y, _grid_w, _grid_h) or not _in_bounds(b.x, b.y, _grid_w, _grid_h):
		return false
	if not _is_passable_for_generation(a) or not _is_passable_for_generation(b):
		return false

	var visited := PackedByteArray()
	visited.resize(_grid_w * _grid_h)
	var q: Array[Vector2i] = [a]
	var head := 0
	visited[_idx(a.x, a.y, _grid_w)] = 1
	var seen := 0
	while head < q.size():
		seen += 1
		if seen > max_nodes:
			break
		var c: Vector2i = q[head]
		head += 1
		if c == b:
			return true
		for d in DIR4:
			var n := c + d
			if not _in_bounds(n.x, n.y, _grid_w, _grid_h):
				continue
			var ii := _idx(n.x, n.y, _grid_w)
			if visited[ii] == 1:
				continue
			if not _is_passable_for_generation(n):
				continue
			visited[ii] = 1
			q.append(n)
	return false


func _force_connect_points_safe(a: Vector2i, b: Vector2i, w: int, h: int) -> void:
	# Thin fallback connector for start/exit spine: uses BFS with the same corridor rules
	# (prevents 2-wide corridors and room-hugging).
	_carve_thin_path_bfs(a, b, w, h)


func _carve_thin_path_bfs(a: Vector2i, b: Vector2i, w: int, h: int, required_room_neighbor: Vector2i = INVALID) -> bool:
	# Finds a 1-wide corridor path from a->b without carving rooms.
	# When required_room_neighbor is provided, allows the final tile (b) to touch that room tile.
	if a == b:
		return true
	if not _in_bounds(a.x, a.y, w, h) or not _in_bounds(b.x, b.y, w, h):
		return false
	if _is_room(a, w) or _is_room(b, w):
		return false

	# BFS state includes incoming direction so we can apply _can_carve_corridor_cell.
	var q: Array[Dictionary] = []
	var head := 0
	var visited := {}
	var parent := {}
	var parent_dir := {}

	visited[a] = true
	q.append({"c": a, "dir": Vector2i.ZERO})

	while head < q.size():
		var cur_d: Dictionary = q[head]
		head += 1
		var c: Vector2i = cur_d["c"]
		if c == b:
			break

		for d in DIR4:
			var n := c + d
			if not _in_bounds(n.x, n.y, w, h):
				continue
			if visited.has(n):
				continue
			if _is_room(n, w):
				continue

			# Existing corridor floors are always traversable.
			if _is_corridor_floor(n, w):
				visited[n] = true
				parent[n] = c
				parent_dir[n] = d
				q.append({"c": n, "dir": d})
				continue

			# For wall tiles, apply the same carve constraints.
			var is_final := (n == b)
			var allow_room_touch := is_final and (required_room_neighbor != INVALID)
			if not _can_carve_corridor_cell(n, d, w, h, allow_room_touch, required_room_neighbor):
				continue

			visited[n] = true
			parent[n] = c
			parent_dir[n] = d
			q.append({"c": n, "dir": d})

	if not visited.has(b):
		return false

	# Reconstruct and carve.
	var path: Array[Vector2i] = []
	var p := b
	while p != a:
		path.append(p)
		p = parent[p]
	path.reverse()

	for cell in path:
		if not _is_corridor_floor(cell, w):
			_set_corridor_floor(cell, w)
	return true


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
	# Update GridModel
	if _grid_model != null:
		_grid_model.set_floor(x, y)

func _is_room(c: Vector2i, w: int) -> bool:
	return _room_mask[_idx(c.x, c.y, w)] == 1

func _set_room(c: Vector2i, w: int) -> void:
	_room_mask[_idx(c.x, c.y, w)] = 1
	# Update GridModel
	if _grid_model != null:
		_grid_model.add_tag(c.x, c.y, GridModel.CellTag.ROOM)

func _is_corridor_floor(c: Vector2i, w: int) -> bool:
	return _grid[_idx(c.x, c.y, w)] == 1 and _room_mask[_idx(c.x, c.y, w)] == 0

func _set_corridor_floor(c: Vector2i, w: int) -> void:
	_grid[_idx(c.x, c.y, w)] = 1
	_room_mask[_idx(c.x, c.y, w)] = 0
	# Update GridModel
	if _grid_model != null:
		_grid_model.set_floor(c.x, c.y)
		_grid_model.add_tag(c.x, c.y, GridModel.CellTag.CORRIDOR)


func _is_doorway_corridor_cell(c: Vector2i, w: int) -> bool:
	# A doorway candidate is a corridor tile adjacent to exactly one room tile.
	if not _is_corridor_floor(c, w):
		return false
	var room_neighbors := 0
	for d in DIR4:
		var n := c + d
		if _in_bounds(n.x, n.y, _grid_w, _grid_h) and _is_room(n, w):
			room_neighbors += 1
	return room_neighbors == 1


func _protect_doorway(doorway_cell: Vector2i, room_edge_cell: Vector2i, w: int, h: int) -> void:
	# Prevent later carving of side cells adjacent to the doorway tile,
	# which would create paths on the side of doors and change their shape.
	if _no_carve_mask.size() != w * h:
		return
	var room_dir: Vector2i = room_edge_cell - doorway_cell
	var perp_dirs: Array[Vector2i] = []
	if room_dir.x != 0:
		perp_dirs = [Vector2i.UP, Vector2i.DOWN]
	else:
		perp_dirs = [Vector2i.LEFT, Vector2i.RIGHT]
	for pd in perp_dirs:
		var b := doorway_cell + pd
		if _in_bounds(b.x, b.y, w, h):
			_no_carve_mask[_idx(b.x, b.y, w)] = 1


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
				# Update GridModel
				if _grid_model != null:
					_grid_model.set_wall(x, y)
					_grid_model.clear_tags(x, y)

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
	# Update GridModel
	if _grid_model != null:
		_grid_model.add_tag(cell.x, cell.y, GridModel.CellTag.DOOR)

func _add_closed_door(cell: Vector2i) -> void:
	if not _doors_closed.has(cell):
		_doors_closed.append(cell)
	_set_door_closed(cell, true)
	# Update GridModel
	if _grid_model != null:
		_grid_model.add_tag(cell.x, cell.y, GridModel.CellTag.DOOR)

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

	var seg1: Array[Vector2i] = _carve_line_corridor(grid, w, h, a, mid)
	carved.append_array(seg1)

	# IMPORTANT: Only attempt the second segment if we actually reached `mid`.
	# Otherwise we'd carve an orphaned corridor from an uncarved `mid`, which can
	# make rooms appear "connected" even though the network can't reach them.
	var reached_mid: bool = (a == mid) or (not seg1.is_empty() and seg1[seg1.size() - 1] == mid)
	if not reached_mid:
		return carved

	var seg2: Array[Vector2i] = _carve_line_corridor(grid, w, h, mid, b, required_room_neighbor)
	carved.append_array(seg2)
	return carved

func _carve_line_corridor(
	_p_grid_unused: PackedByteArray,
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
	if _no_carve_mask.size() == w * h and _no_carve_mask[_idx(c.x, c.y, w)] == 1:
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
	# Keep only border doors (entrance/exit)
	var keep_open: Array[Vector2i] = []
	for d in _doors_open:
		if d.x == 0 or d.x == _grid_w - 1 or d.y == 0 or d.y == _grid_h - 1:
			keep_open.append(d)
	_doors_open = keep_open

	# Rebuild closed doors
	_doors_closed.clear()
	for i in range(_door_closed_mask.size()):
		_door_closed_mask[i] = 0

	# Find true room entrances: corridor tiles with exactly 1 room neighbor
	# that are NOT part of a corridor running parallel to the room wall
	for y in range(_grid_h):
		for x in range(_grid_w):
			var c := Vector2i(x, y)
			
			# Must be corridor floor
			if not _is_corridor_floor(c, _grid_w):
				continue
			
			# Skip border tiles
			if x == 0 or x == _grid_w - 1 or y == 0 or y == _grid_h - 1:
				continue
			
			# Count room neighbors and find the direction
			var room_neighbors := 0
			var room_dir := Vector2i.ZERO
			
			for dir in DIR4:
				var n := c + dir
				if _in_bounds(n.x, n.y, _grid_w, _grid_h) and _is_room(n, _grid_w):
					room_neighbors += 1
					room_dir = dir
			
			# Only consider tiles with exactly 1 room neighbor
			if room_neighbors != 1:
				continue
			
			# Enforce a clean 1-tile doorway: the corridor tile next to the room must be a dead-end
			# (one corridor neighbor away from the room; no side corridors).
			var away_dir := -room_dir
			var away_pos := c + away_dir
			if not _in_bounds(away_pos.x, away_pos.y, _grid_w, _grid_h):
				continue
			if not _is_corridor_floor(away_pos, _grid_w):
				continue

			var perp_dirs: Array[Vector2i] = []
			if room_dir.x != 0:
				perp_dirs = [Vector2i.UP, Vector2i.DOWN]
			else:
				perp_dirs = [Vector2i.LEFT, Vector2i.RIGHT]
			var has_side_corridor := false
			for pd in perp_dirs:
				var pn := c + pd
				if _in_bounds(pn.x, pn.y, _grid_w, _grid_h) and _is_corridor_floor(pn, _grid_w):
					has_side_corridor = true
					break
			if has_side_corridor:
				continue

			var corridor_neighbors := 0
			for d2 in DIR4:
				var n2 := c + d2
				if _in_bounds(n2.x, n2.y, _grid_w, _grid_h) and _is_corridor_floor(n2, _grid_w):
					corridor_neighbors += 1
			if corridor_neighbors != 1:
				continue

			_add_closed_door(c)
			_protect_doorway(c, c + room_dir, _grid_w, _grid_h)


func _is_valid_room_entrance(corridor_cell: Vector2i, room_cell: Vector2i) -> bool:
	# Determine the direction from corridor to room
	var to_room := room_cell - corridor_cell
	
	# Check perpendicular directions from the corridor tile
	var perp_dirs: Array[Vector2i] = []
	if to_room.x != 0:  # Room is left/right
		perp_dirs = [Vector2i.UP, Vector2i.DOWN]
	else:  # Room is up/down
		perp_dirs = [Vector2i.LEFT, Vector2i.RIGHT]
	
	# Count how many perpendicular sides are corridor
	var perp_corridor_count := 0
	for pd in perp_dirs:
		var pn := corridor_cell + pd
		if _in_bounds(pn.x, pn.y, _grid_w, _grid_h) and _is_corridor_floor(pn, _grid_w):
			perp_corridor_count += 1
	
	# Check opposite direction (away from room)
	var away_from_room := -to_room
	var opposite_pos := corridor_cell + away_from_room
	var opposite_is_corridor := false
	if _in_bounds(opposite_pos.x, opposite_pos.y, _grid_w, _grid_h):
		opposite_is_corridor = _is_corridor_floor(opposite_pos, _grid_w)
	
	# It's a parallel corridor wall (not entrance) if BOTH perp sides AND opposite are corridors
	var is_parallel_wall := (perp_corridor_count == 2) and opposite_is_corridor
	
	# Valid entrance = NOT a parallel wall
	return not is_parallel_wall


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

	if debug_dump_on_fail:
		_dump_grid_debug("no_path_after_retries")

	_force_connect_start_to_exit()
	_rebuild_room_doors()
	_render_grid()

	if debug_dump_on_fail:
		_dump_grid_debug("after_force_connect")
	# last attempt (shows something rather than nothing)
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

	if not _is_passable_for_generation(s) or not _is_passable_for_generation(e):
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
			if not _is_passable_for_generation(n):
				continue
			visited[ii] = 1
			q.append(n)

	return false

func _is_passable_for_generation(c: Vector2i) -> bool:
	if _grid_w <= 0 or _grid_h <= 0:
		return false
	if not _in_bounds(c.x, c.y, _grid_w, _grid_h):
		return false
	# Closed doors are still openable, so treat them as passable for connectivity.
	if is_door_closed(c):
		return true
	return _grid[_idx(c.x, c.y, _grid_w)] == 1

func _force_connect_start_to_exit() -> void:
	var s := _step_inside(start_cell, _grid_w, _grid_h)
	var e := _step_inside(exit_cell, _grid_w, _grid_h)
	if not _in_bounds(s.x, s.y, _grid_w, _grid_h):
		return
	if not _in_bounds(e.x, e.y, _grid_w, _grid_h):
		return

	var horiz_first: bool = abs(s.x - e.x) >= abs(s.y - e.y)
	var mid := (Vector2i(e.x, s.y) if horiz_first else Vector2i(s.x, e.y))

	_force_line_carve(s, mid)
	_force_line_carve(mid, e)

func _force_line_carve(a: Vector2i, b: Vector2i) -> void:
	if a.x != b.x and a.y != b.y:
		return
	var dx := signi(b.x - a.x)
	var dy := signi(b.y - a.y)
	var p := a
	while p != b:
		p = Vector2i(p.x + dx, p.y + dy)
		if not _in_bounds(p.x, p.y, _grid_w, _grid_h):
			break
		_grid[_idx(p.x, p.y, _grid_w)] = 1
		_room_mask[_idx(p.x, p.y, _grid_w)] = 0
		# Update GridModel
		if _grid_model != null:
			_grid_model.set_floor(p.x, p.y)
			_grid_model.add_tag(p.x, p.y, GridModel.CellTag.CORRIDOR)

func _dump_grid_debug(tag: String) -> void:
	print("[MazeGen] dump:", tag, " w=", _grid_w, " h=", _grid_h, " level=", level, " run=", run, " seed=", rng_seed)
	for y in range(_grid_h):
		var row := ""
		for x in range(_grid_w):
			var c := Vector2i(x, y)
			var ch := "#"
			if c == start_cell:
				ch = "S"
			elif c == exit_cell:
				ch = "E"
			elif is_door_closed(c):
				ch = "D"
			elif _doors_open.has(c):
				ch = "O"
			elif _grid[_idx(x, y, _grid_w)] == 1:
				ch = "."
			row += ch
		print(row)
