## Logical grid data model for procedurally-generated levels.
##
## Stores the maze/level layout in a 2D array of cells before rendering to TileMaps.
## Each cell tracks floor/wall state and optional tags (room, corridor, etc.).
## This separates generation logic from rendering and provides a query-able model.
extends RefCounted
class_name GridModel

## Cell flags/types
enum CellType {
	WALL = 0,
	FLOOR = 1
}

## Optional cell tags for maze features
enum CellTag {
	NONE = 0,
	ROOM = 1,      # Part of a room/hub
	CORRIDOR = 2,  # Narrow corridor
	DOOR = 4       # Door location (can be combined with floor)
}

## Grid dimensions
var width: int = 0
var height: int = 0

## 2D array: cells[y][x] = { type: CellType, tags: int (bitfield) }
## Access via [y][x] for performance (cache-friendly row-major)
var cells: Array = []

# --------------------------------------------------------------------
# Initialization
# --------------------------------------------------------------------

func _init(w: int, h: int) -> void:
	width = w
	height = h
	_allocate_grid()

func _allocate_grid() -> void:
	cells.clear()
	cells.resize(height)
	for y in range(height):
		var row: Array = []
		row.resize(width)
		for x in range(width):
			row[x] = {"type": CellType.WALL, "tags": CellTag.NONE}
		cells[y] = row

# --------------------------------------------------------------------
# Core queries
# --------------------------------------------------------------------

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height

func get_cell(x: int, y: int) -> Dictionary:
	if not in_bounds(x, y):
		return {"type": CellType.WALL, "tags": CellTag.NONE}
	return cells[y][x]

func is_floor(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return cells[y][x]["type"] == CellType.FLOOR

func is_wall(x: int, y: int) -> bool:
	return not is_floor(x, y)

func has_tag(x: int, y: int, tag: CellTag) -> bool:
	if not in_bounds(x, y):
		return false
	return (cells[y][x]["tags"] & tag) != 0

func is_room(x: int, y: int) -> bool:
	return has_tag(x, y, CellTag.ROOM)

func is_corridor(x: int, y: int) -> bool:
	return has_tag(x, y, CellTag.CORRIDOR)

func is_door(x: int, y: int) -> bool:
	return has_tag(x, y, CellTag.DOOR)

# --------------------------------------------------------------------
# Mutations
# --------------------------------------------------------------------

func set_floor(x: int, y: int) -> void:
	if in_bounds(x, y):
		cells[y][x]["type"] = CellType.FLOOR

func set_wall(x: int, y: int) -> void:
	if in_bounds(x, y):
		cells[y][x]["type"] = CellType.WALL

func set_solid(x: int, y: int) -> void:
	set_wall(x, y)

func add_tag(x: int, y: int, tag: CellTag) -> void:
	if in_bounds(x, y):
		cells[y][x]["tags"] |= tag

func remove_tag(x: int, y: int, tag: CellTag) -> void:
	if in_bounds(x, y):
		cells[y][x]["tags"] &= ~tag

func clear_tags(x: int, y: int) -> void:
	if in_bounds(x, y):
		cells[y][x]["tags"] = CellTag.NONE

func set_room_floor(x: int, y: int) -> void:
	set_floor(x, y)
	add_tag(x, y, CellTag.ROOM)

func set_corridor_floor(x: int, y: int) -> void:
	set_floor(x, y)
	add_tag(x, y, CellTag.CORRIDOR)

func set_door(x: int, y: int) -> void:
	# Doors are floors with a door tag
	set_floor(x, y)
	add_tag(x, y, CellTag.DOOR)

# --------------------------------------------------------------------
# Neighbors
# --------------------------------------------------------------------

## Returns 4-directional neighbor coordinates (not bounds-checked)
func neighbors4(x: int, y: int) -> Array[Vector2i]:
	return [
		Vector2i(x + 1, y),
		Vector2i(x - 1, y),
		Vector2i(x, y + 1),
		Vector2i(x, y - 1)
	]

## Returns valid (in-bounds) 4-directional neighbors
func neighbors4_valid(x: int, y: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for n in neighbors4(x, y):
		if in_bounds(n.x, n.y):
			result.append(n)
	return result

## Returns 8-directional neighbor coordinates (not bounds-checked)
func neighbors8(x: int, y: int) -> Array[Vector2i]:
	return [
		Vector2i(x + 1, y),
		Vector2i(x - 1, y),
		Vector2i(x, y + 1),
		Vector2i(x, y - 1),
		Vector2i(x + 1, y + 1),
		Vector2i(x + 1, y - 1),
		Vector2i(x - 1, y + 1),
		Vector2i(x - 1, y - 1)
	]

# --------------------------------------------------------------------
# Bulk operations
# --------------------------------------------------------------------

## Get all floor cells in the grid
func get_all_floor_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			if is_floor(x, y):
				result.append(Vector2i(x, y))
	return result

## Get all cells with a specific tag
func get_cells_with_tag(tag: CellTag) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			if has_tag(x, y, tag):
				result.append(Vector2i(x, y))
	return result

## Clear the entire grid to walls
func clear_all() -> void:
	for y in range(height):
		for x in range(width):
			cells[y][x]["type"] = CellType.WALL
			cells[y][x]["tags"] = CellTag.NONE

# --------------------------------------------------------------------
# Debug/visualization
# --------------------------------------------------------------------

func to_debug_string() -> String:
	var s := "[GridModel %dx%d]\n" % [width, height]
	for y in range(height):
		for x in range(width):
			var ch := "#"
			if is_floor(x, y):
				if is_door(x, y):
					ch = "D"
				elif is_room(x, y):
					ch = "R"
				elif is_corridor(x, y):
					ch = "."
				else:
					ch = " "
			s += ch
		s += "\n"
	return s
