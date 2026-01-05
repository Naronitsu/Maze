# FogOfWar.gd
extends Node2D
class_name FogOfWar

@export var maze_path: NodePath
@export var player_path: NodePath
@export var canvas_modulate_path: NodePath  # drag your CanvasModulate here (optional)

@export var vision_radius_tiles: int = 6
@export var explored_alpha: float = 0.35   # explored-but-not-visible veil
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

	# If you use CanvasModulate to darken the world, counteract it so fog stays readable.
	_apply_modulate_compensation()

	# First reveal after everything is ready
	call_deferred("_update_fog")

func _process(_delta: float) -> void:
	if update_every_frame:
		_update_fog()

func reveal_now() -> void:
	_update_fog()

func _apply_modulate_compensation() -> void:
	if _cm == null or _sprite == null:
		return

	var c: Color = _cm.color
	# Avoid divide-by-zero; this effectively cancels the CanvasModulate tint.
	var inv := Color(
		1.0 / max(c.r, 0.001),
		1.0 / max(c.g, 0.001),
		1.0 / max(c.b, 0.001),
		1.0
	)
	_sprite.self_modulate = inv

func _update_fog() -> void:
	if _maze == null or _player == null or _w <= 0 or _h <= 0:
		return

	# Safely read player's cell (Player.gd should expose `var cell: Vector2i`)
	var cell_val: Variant = _player.get("cell")
	if cell_val == null:
		return
	var pc: Vector2i = cell_val as Vector2i

	# Base: unseen (black) or explored (greyed out)
	for y in range(_h):
		for x in range(_w):
			var i: int = _idx(x, y)
			_img.set_pixel(
				x, y,
				Color(0, 0, 0, explored_alpha if _explored[i] == 1 else unseen_alpha)
			)

	# Reveal current visibility radius and mark explored
	var r: int = vision_radius_tiles
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue

			var x: int = pc.x + dx
			var y: int = pc.y + dy
			if x < 0 or y < 0 or x >= _w or y >= _h:
				continue

			var i2: int = _idx(x, y)
			_explored[i2] = 1
			_img.set_pixel(x, y, Color(0, 0, 0, 0.0)) # visible = clear

	_tex.update(_img)

func _idx(x: int, y: int) -> int:
	return y * _w + x
