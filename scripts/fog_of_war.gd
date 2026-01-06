# FogOfWar.gd
extends Node2D
class_name FogOfWar

@export var maze_path: NodePath
@export var player_path: NodePath
@export var canvas_modulate_path: NodePath  # optional; set to your CanvasModulate node

@export var vision_radius_tiles: int = 6
@export var explored_alpha: float = 0.55   # explored-but-not-currently-visible veil
@export var unseen_alpha: float = 1.0      # unseen veil
@export var update_every_frame: bool = false

var _maze: MazeLayer
var _player: Node
var _cm: CanvasModulate

var _w: int
var _h: int
var _explored: PackedByteArray

var _img: Image
var _tex: ImageTexture
var _sprite: Sprite2D

# world-space origin of cell (0,0) as returned by map_to_local (usually cell center)
var _origin_global: Vector2
# tile size in world units (computed from TileMap conversions)
var _tile_px: Vector2

func _ready() -> void:
	_maze = get_node_or_null(maze_path) as MazeLayer
	_player = get_node_or_null(player_path)
	_cm = get_node_or_null(canvas_modulate_path) as CanvasModulate

	if _maze == null:
		push_error("FogOfWar: bad maze_path")
		return
	if _player == null:
		push_error("FogOfWar: bad player_path")
		return

	# IMPORTANT (Fix 1):
	# CanvasModulate should NOT darken the whole world if you want to see explored tiles behind you.
	if _cm != null:
		_cm.color = Color(1, 1, 1, 1)

	# Wait until the maze has generated and grid sizes are known
	call_deferred("_init_fog")

func _init_fog() -> void:
	if _maze._grid_w <= 0 or _maze._grid_h <= 0:
		call_deferred("_init_fog")
		return

	_w = _maze._grid_w
	_h = _maze._grid_h

	_explored = PackedByteArray()
	_explored.resize(_w * _h) # default 0

	_img = Image.create(_w, _h, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, unseen_alpha))

	_tex = ImageTexture.create_from_image(_img)

	_sprite = Sprite2D.new()
	_sprite.texture = _tex
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = 999
	add_child(_sprite)

	# Compute world-space origin and per-cell world size robustly
	_origin_global = _maze.to_global(_maze.map_to_local(Vector2i(0, 0)))
	var p10: Vector2 = _maze.to_global(_maze.map_to_local(Vector2i(1, 0)))
	var p01: Vector2 = _maze.to_global(_maze.map_to_local(Vector2i(0, 1)))

	_tile_px = Vector2((p10 - _origin_global).length(), (p01 - _origin_global).length())

	# Position fog so pixel (0,0) corresponds to the top-left of cell (0,0)
	_sprite.global_position = _origin_global - (_tile_px * 0.5)
	_sprite.scale = _tile_px

	# First reveal after everything is ready
	call_deferred("reveal_now")

func _process(_delta: float) -> void:
	if update_every_frame:
		reveal_now()

func reveal_now() -> void:
	if _maze == null or _player == null:
		return
	if _w <= 0 or _h <= 0:
		return
	if _img == null or _tex == null:
		return

	# player cell from actual position (robust after teleports/resets)
	var pc: Vector2i = _maze.local_to_map(_maze.to_local(_player.global_position))
	pc.x = clampi(pc.x, 0, _w - 1)
	pc.y = clampi(pc.y, 0, _h - 1)

	# base: unseen/explored
	for y in range(_h):
		for x in range(_w):
			var i := y * _w + x
			var a := explored_alpha if _explored[i] == 1 else unseen_alpha
			_img.set_pixel(x, y, Color(0, 0, 0, a))

	# clear current visibility (circle radius)
	var r := vision_radius_tiles
	var r2 := r * r
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r2:
				continue
			var x := pc.x + dx
			var y := pc.y + dy
			if x < 0 or y < 0 or x >= _w or y >= _h:
				continue

			var idx := y * _w + x
			_explored[idx] = 1
			_img.set_pixel(x, y, Color(0, 0, 0, 0.0))

	_tex.update(_img)

func _idx(x: int, y: int) -> int:
	return y * _w + x

func rebuild_for_current_maze() -> void:
	if _maze == null:
		return

	var new_w: int = _maze._grid_w
	var new_h: int = _maze._grid_h

	# If the maze hasn't finished setting size yet, try next frame
	if new_w <= 0 or new_h <= 0:
		call_deferred("rebuild_for_current_maze")
		return

	# If fog hasn't been created yet (first run), initialize normally
	if _sprite == null or _tex == null or _img == null:
		call_deferred("_init_fog")
		call_deferred("reveal_now")
		return

	var size_changed: bool = (new_w != _w) or (new_h != _h)
	if size_changed:
		_build_from_maze_size(new_w, new_h)
	else:
		reset_fog()

func reset_fog() -> void:
	if _explored.size() == 0:
		return
	for i in range(_explored.size()):
		_explored[i] = 0

	if _img:
		_img.fill(Color(0, 0, 0, unseen_alpha))
		if _tex:
			_tex.update(_img)

func _build_from_maze_size(new_w: int, new_h: int) -> void:
	_w = new_w
	_h = new_h

	_explored = PackedByteArray()
	_explored.resize(_w * _h) # defaults to 0

	_img = Image.create(_w, _h, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, unseen_alpha))

	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex = ImageTexture.create_from_image(_img) # simplest + reliable

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.z_index = 999
		add_child(_sprite)

	_sprite.texture = _tex

	# Keep your existing alignment logic (tile size + origin).
	# If you already compute these in _init_fog(), reuse the same code here:
	_origin_global = _maze.to_global(_maze.map_to_local(Vector2i(0, 0)))
	var p10: Vector2 = _maze.to_global(_maze.map_to_local(Vector2i(1, 0)))
	var p01: Vector2 = _maze.to_global(_maze.map_to_local(Vector2i(0, 1)))
	_tile_px = Vector2((p10 - _origin_global).length(), (p01 - _origin_global).length())

	_sprite.global_position = _origin_global - (_tile_px * 0.5)
	_sprite.scale = _tile_px
