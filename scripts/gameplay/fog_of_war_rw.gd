## Fog of war system with vision rendering and explored memory.
## Uses raycasting for vision polygons; maintains current visibility and explored memory.
extends Control
class_name FogOfWarRW

#region Exported (Inspector)
@export_category("Dependencies")
@export var player: Node2D
@export var cam: Camera2D
@export var layer: TileMapLayer

# Backward compatibility with scene files
@export var player_path: NodePath
@export var camera_path: NodePath
@export var layer_path: NodePath

@export_category("Configuration")
@export var wall_mask: int = 1 << 0
@export var show_mask_preview: bool = false
#endregion

#region Onready
@onready var viewport: SubViewport = $MaskViewport
@onready var vision_poly: Polygon2D = $MaskViewport/MaskRoot/VisionMask
@onready var halo_poly: Polygon2D = $MaskViewport/MaskRoot/HaloMask

# Explored (world-sized) mask viewport
@onready var explored_viewport: SubViewport = $ExploredViewport
@onready var explored_vision: Polygon2D = $ExploredViewport/MaskRoot/VisionMask
@onready var explored_halo: Polygon2D = $ExploredViewport/MaskRoot/HaloMask

@onready var darkness: ColorRect = $Darkness
@onready var mask_preview: TextureRect = get_node_or_null("MaskPreview") as TextureRect
#endregion

#region Public Properties
var facing: Vector2 = Vector2.RIGHT
var suspended: bool = false
#endregion

#region Private Fields
var _awaiting_level_start: bool = true
var _pending_reveal: bool = false
var _needs_reset_on_next_start: bool = false
var _explored_base: Sprite2D

var maze_origin_world: Vector2
var maze_size_world: Vector2
var tile_size: Vector2

var _player_stats: Stats

const _EXPLORED_DECAY_SHADER: Shader = preload("res://shaders/fog_explored_decay_mul.gdshader")

var _explored_decay_sprite: Sprite2D
var _explored_decay_mat: ShaderMaterial
var _explored_decay_white_tex: Texture2D

# Sticky reveals (drawn AFTER decay so they don't fade)
var _sticky_room_poly: Polygon2D
var _sticky_door_poly: Polygon2D

var _maze: DungeonMazeLayer
var _room_rects: Array[Rect2i] = []
var _room_hold_active: bool = false
var _room_hold_rect: Rect2i = Rect2i()
var _room_entry_door_cell: Vector2i = Vector2i(2147483647, 2147483647)

const _EXPLORED_DECAY_STEP_SEC := 0.10
var _explored_decay_accum_sec: float = 0.0

const MASK_LAYER_BIT := 19
const MASK_LAYER := 1 << MASK_LAYER_BIT

const HIT_INSET_PX := 2.0

const DOOR_STEP_MIN_PX := 2.0
const DOOR_STEP_FRACTION_OF_TILE := 0.25
#endregion

#region Lifecycle
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Initialize from NodePath exports if direct references not set (backward compatibility)
	if player == null and player_path != NodePath():
		player = get_node_or_null(player_path) as Node2D
	if cam == null and camera_path != NodePath():
		cam = get_node_or_null(camera_path) as Camera2D
	if layer == null and layer_path != NodePath():
		layer = get_node_or_null(layer_path) as TileMapLayer

	_player_stats = player.get_node_or_null("Stats") as Stats

	# Validate required references
	if layer == null:
		# Try fallback to find TileMapLayer
		layer = get_node_or_null("../TileMap/MazeLayer") as TileMapLayer
		if layer == null:
			push_error("[FogOfWar] TileMapLayer reference not found - fog system will not work")
			return

	if player == null:
		player = get_node_or_null("../Player") as Node2D
		if player == null:
			push_error("[FogOfWar] Player reference not found - fog system will not work")
			return

	if cam == null:
		cam = get_node_or_null("../Camera2D") as Camera2D
		if cam == null:
			push_error("[FogOfWar] Camera reference not found - fog system will not work")
			return

	# Keep fog frozen until the level is fully ready.
	suspended = true
	_awaiting_level_start = true
	EventBus.level_started.connect(_on_level_started)
	EventBus.level_transitioning.connect(_on_level_transitioning)
	EventBus.player_moved.connect(_on_player_moved)

	await _wait_for_tiles()

	_compute_layer_bounds()
	_setup_viewports()
	_setup_darkness_shader()
	_ensure_explored_base()
	_ensure_explored_decay_sprite()
	_ensure_sticky_polys()

	# Make mask "ink" explicitly white
	vision_poly.color = Color(1, 1, 1, 1)
	halo_poly.color = Color(1, 1, 1, 1)
	explored_vision.color = Color(1, 1, 1, 1)
	explored_halo.color = Color(1, 1, 1, 1)

	# Start explored memory empty, then accumulate forever
	await _clear_explored_once()

	if mask_preview != null:
		mask_preview.visible = show_mask_preview
		mask_preview.texture = explored_viewport.get_texture()

	# If level_started already fired while we were initializing, resume now.
	if _pending_reveal and not _awaiting_level_start:
		_resume_after_level_start()
#endregion

#region Signal Handlers
func _on_level_started(_spawn_cell: Vector2i, maze_node: DungeonMazeLayer) -> void:
	_maze = maze_node
	_room_rects = (
		_maze.get_room_rects() if _maze != null and _maze.has_method("get_room_rects") else []
	)
	_room_hold_active = false
	_room_hold_rect = Rect2i()
	_room_entry_door_cell = Vector2i(2147483647, 2147483647)
	_update_sticky_polys()
	_awaiting_level_start = false
	if _needs_reset_on_next_start:
		_needs_reset_on_next_start = false
		await reset_fog_for_level()
	_pending_reveal = true
	_resume_after_level_start()


func _on_level_transitioning() -> void:
	suspended = true
	_awaiting_level_start = true
	_pending_reveal = false
	_needs_reset_on_next_start = true
	_room_hold_active = false
	_room_hold_rect = Rect2i()
	_room_entry_door_cell = Vector2i(2147483647, 2147483647)
	_update_sticky_polys()


func _on_player_moved(_from_cell: Vector2i, to_cell: Vector2i) -> void:
	if suspended or _awaiting_level_start:
		return
	if _maze == null:
		_maze = layer as DungeonMazeLayer
	if _room_rects.is_empty() and _maze != null and _maze.has_method("get_room_rects"):
		_room_rects = _maze.get_room_rects()

	# Activate hold when stepping onto a room-connected door tile.
	if not _room_hold_active and _is_room_connected_door(to_cell):
		_room_hold_active = true
		_room_entry_door_cell = to_cell
		_room_hold_rect = _room_rect_connected_to_door(to_cell)
		_update_sticky_polys()
		return

	# While holding, keep it active while inside the room OR on a connected doorway tile.
	if _room_hold_active:
		var still_in := _room_hold_rect.size != Vector2i.ZERO and _room_hold_rect.has_point(to_cell)
		var still_on_door := _is_door_connected_to_rect(to_cell, _room_hold_rect)
		if still_in or still_on_door:
			_update_sticky_polys()
			return

		# Left the room: allow forgetting again.
		_room_hold_active = false
		_room_hold_rect = Rect2i()
		_room_entry_door_cell = Vector2i(2147483647, 2147483647)
		_update_sticky_polys()
#endregion

#region Lifecycle (_process)
func _process(dt: float) -> void:
	_push_shader_uniforms()
	_update_explored_decay(dt)
	_update_masks()
	# Keep sticky polys up to date in case bounds shift (rare) or we want to keep door/room pinned.
	if _room_hold_active:
		_update_sticky_polys()
#endregion

#region Private Methods (setup / decay)
func _get_explored_decay_white_tex() -> Texture2D:
	if _explored_decay_white_tex != null:
		return _explored_decay_white_tex

	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	_explored_decay_white_tex = ImageTexture.create_from_image(img)
	return _explored_decay_white_tex


func _ensure_explored_decay_sprite() -> void:
	if explored_viewport == null:
		return
	if _explored_decay_sprite != null and is_instance_valid(_explored_decay_sprite):
		return

	_explored_decay_mat = ShaderMaterial.new()
	_explored_decay_mat.shader = _EXPLORED_DECAY_SHADER
	_explored_decay_mat.set_shader_parameter("amount", 0.0)

	_explored_decay_sprite = Sprite2D.new()
	_explored_decay_sprite.name = "ExploredDecay"
	_explored_decay_sprite.centered = false
	_explored_decay_sprite.position = Vector2.ZERO
	# Draw AFTER the explored mask polygons so it decays the accumulated explored texture.
	# (Current-vision areas will be re-stamped next frame, so they won't "disappear".)
	_explored_decay_sprite.z_index = 1000
	_explored_decay_sprite.texture = _get_explored_decay_white_tex()
	_explored_decay_sprite.material = _explored_decay_mat

	var root := explored_viewport.get_node_or_null("MaskRoot") as Node2D
	if root != null:
		root.add_child(_explored_decay_sprite)
	else:
		explored_viewport.add_child(_explored_decay_sprite)
	_update_explored_decay_sprite_size()


func _ensure_sticky_polys() -> void:
	if explored_viewport == null:
		return
	var root := explored_viewport.get_node_or_null("MaskRoot") as Node2D
	if root == null:
		return

	if _sticky_room_poly == null or not is_instance_valid(_sticky_room_poly):
		_sticky_room_poly = Polygon2D.new()
		_sticky_room_poly.name = "StickyRoom"
		_sticky_room_poly.z_index = 2000
		_sticky_room_poly.color = Color(1, 1, 1, 1)
		root.add_child(_sticky_room_poly)

	if _sticky_door_poly == null or not is_instance_valid(_sticky_door_poly):
		_sticky_door_poly = Polygon2D.new()
		_sticky_door_poly.name = "StickyDoor"
		_sticky_door_poly.z_index = 2001
		_sticky_door_poly.color = Color(1, 1, 1, 1)
		root.add_child(_sticky_door_poly)


func _update_sticky_polys() -> void:
	_ensure_sticky_polys()
	if _sticky_room_poly == null or _sticky_door_poly == null:
		return

	if not _room_hold_active:
		_sticky_room_poly.polygon = PackedVector2Array()
		_sticky_door_poly.polygon = PackedVector2Array()
		return

	# Sticky room rect
	_sticky_room_poly.polygon = _room_rect_to_explored_poly(_room_hold_rect)
	# Sticky door tile
	_sticky_door_poly.polygon = _cell_to_explored_tile_poly(_room_entry_door_cell)


func _room_rect_to_explored_poly(rect: Rect2i) -> PackedVector2Array:
	if rect.size == Vector2i.ZERO:
		return PackedVector2Array()
	var tl_cell := rect.position
	var br_cell := rect.end - Vector2i.ONE
	var tl_world := _cell_center_world(tl_cell)
	var br_world := _cell_center_world(br_cell)
	if tile_size == Vector2.ZERO:
		return PackedVector2Array()
	var half := tile_size * 0.5
	var min_world := Vector2(min(tl_world.x, br_world.x), min(tl_world.y, br_world.y)) - half
	var max_world := Vector2(max(tl_world.x, br_world.x), max(tl_world.y, br_world.y)) + half
	return PackedVector2Array(
		[
			min_world - maze_origin_world,
			Vector2(max_world.x, min_world.y) - maze_origin_world,
			max_world - maze_origin_world,
			Vector2(min_world.x, max_world.y) - maze_origin_world,
		]
	)


func _cell_to_explored_tile_poly(cell: Vector2i) -> PackedVector2Array:
	if tile_size == Vector2.ZERO:
		return PackedVector2Array()
	var c_world := _cell_center_world(cell)
	var half := tile_size * 0.5
	var min_world := c_world - half
	var max_world := c_world + half
	return PackedVector2Array(
		[
			min_world - maze_origin_world,
			Vector2(max_world.x, min_world.y) - maze_origin_world,
			max_world - maze_origin_world,
			Vector2(min_world.x, max_world.y) - maze_origin_world,
		]
	)


func _cell_center_world(cell: Vector2i) -> Vector2:
	if layer == null:
		return Vector2.ZERO
	return layer.to_global(layer.map_to_local(cell))


func _is_room_connected_door(cell: Vector2i) -> bool:
	if _maze == null:
		_maze = layer as DungeonMazeLayer
	if _maze == null or not _maze.has_method("is_door_cell"):
		return false
	if not bool(_maze.call("is_door_cell", cell)):
		return false
	return _room_rect_connected_to_door(cell).size != Vector2i.ZERO


func _room_rect_connected_to_door(door_cell: Vector2i) -> Rect2i:
	for r: Rect2i in _room_rects:
		if _is_door_connected_to_rect(door_cell, r):
			return r
	return Rect2i()


func _is_door_connected_to_rect(door_cell: Vector2i, rect: Rect2i) -> bool:
	if rect.size == Vector2i.ZERO:
		return false
	# A connected doorway tile is adjacent (4-neighbor) to a room cell.
	var nbs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d: Vector2i in nbs:
		if rect.has_point(door_cell + d):
			return true
	return false


func _update_explored_decay_sprite_size() -> void:
	if explored_viewport == null:
		return
	if _explored_decay_sprite == null or not is_instance_valid(_explored_decay_sprite):
		return
	var s := explored_viewport.size
	if s.x <= 0 or s.y <= 0:
		return
	# The decay sprite uses a 1x1 texture; scale directly to viewport pixels.
	_explored_decay_sprite.scale = Vector2(float(s.x), float(s.y))


func _update_explored_decay(dt: float) -> void:
	if _explored_decay_sprite == null or not is_instance_valid(_explored_decay_sprite):
		return
	if _explored_decay_mat == null:
		return

	# Only decay while actively running and memory is enabled.
	if suspended or _awaiting_level_start or not GameConfig.fog_enable_memory:
		_explored_decay_sprite.visible = false
		_explored_decay_accum_sec = 0.0
		_explored_decay_mat.set_shader_parameter("amount", 0.0)
		return

	var rate := maxf(0.0, GameConfig.fog_memory_forget_rate_per_second)
	if rate <= 0.0:
		_explored_decay_sprite.visible = false
		_explored_decay_accum_sec = 0.0
		_explored_decay_mat.set_shader_parameter("amount", 0.0)
		return

	_explored_decay_sprite.visible = true

	# SubViewport textures are typically 8-bit per channel, so tiny per-frame
	# subtractions (e.g. rate=0.15 at 60fps => 0.0025) can quantize to "no change".
	# Accumulate time and apply decay in small steps so it is visible and tuneable.
	_explored_decay_accum_sec += dt
	var steps := int(floor(_explored_decay_accum_sec / _EXPLORED_DECAY_STEP_SEC))
	if steps <= 0:
		_explored_decay_mat.set_shader_parameter("amount", 0.0)
		return

	_explored_decay_accum_sec -= float(steps) * _EXPLORED_DECAY_STEP_SEC
	var amount := clampf(rate * _EXPLORED_DECAY_STEP_SEC * float(steps), 0.0, 1.0)
	_explored_decay_mat.set_shader_parameter("amount", amount)


#region Public Methods
func set_player_and_presence(p: Node2D, _presence: Node) -> void:
	player = p


func set_facing_cardinal(dir: Variant) -> void:
	var v: Vector2
	if dir is Vector2:
		v = dir
	elif dir is Vector2i:
		v = Vector2(dir.x, dir.y)
	else:
		return

	if v == Vector2.LEFT or v == Vector2.RIGHT or v == Vector2.UP or v == Vector2.DOWN:
		facing = v


func set_suspended(v: bool) -> void:
	suspended = v


func reveal_now() -> void:
	_update_masks()
#endregion

#region Private Methods (bounds / viewports)
func _compute_layer_bounds() -> void:
	if layer == null:
		push_error("[FogOfWar._compute_layer_bounds] layer is null")
		return

	var used: Rect2i = layer.get_used_rect()

	var ts := layer.tile_set
	if ts == null:
		var parent_tm := layer.get_parent()
		if parent_tm is TileMap:
			ts = (parent_tm as TileMap).tile_set
	tile_size = Vector2(ts.tile_size)

	# Use two corners so scaling/transform/cell layout doesn't break the size math
	var local_a: Vector2 = layer.map_to_local(used.position)
	var local_b: Vector2 = layer.map_to_local(used.position + used.size)

	var world_a: Vector2 = layer.to_global(local_a)
	var world_b: Vector2 = layer.to_global(local_b)

	maze_origin_world = Vector2(min(world_a.x, world_b.x), min(world_a.y, world_b.y))
	maze_size_world = Vector2(abs(world_b.x - world_a.x), abs(world_b.y - world_a.y))

	maze_origin_world -= Vector2(1, 1)
	maze_size_world += Vector2(2, 2)

	maze_size_world.x = max(maze_size_world.x, 1.0)
	maze_size_world.y = max(maze_size_world.y, 1.0)


func _setup_viewports() -> void:
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var want_screen := Vector2i(int(screen_size.x), int(screen_size.y))

	viewport.transparent_bg = true
	explored_viewport.transparent_bg = true

	if viewport.size != want_screen:
		viewport.size = want_screen
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var want_world := Vector2i(int(ceil(maze_size_world.x)), int(ceil(maze_size_world.y)))
	if explored_viewport.size != want_world:
		explored_viewport.size = want_world
	explored_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	explored_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER

	# Rebind textures in case render targets were recreated
	var mat := darkness.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("current_tex", viewport.get_texture())
		mat.set_shader_parameter("explored_tex", explored_viewport.get_texture())

	_update_explored_decay_sprite_size()


func _setup_darkness_shader() -> void:
	var mat := darkness.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = preload("res://shaders/fog_darkness_world_memory.gdshader")
		darkness.material = mat

	mat.set_shader_parameter("current_tex", viewport.get_texture())
	mat.set_shader_parameter("explored_tex", explored_viewport.get_texture())
	mat.set_shader_parameter("darkness_alpha", GameConfig.fog_darkness_alpha)
	mat.set_shader_parameter("explored_alpha", GameConfig.fog_explored_alpha)
	mat.set_shader_parameter("enable_memory", GameConfig.fog_enable_memory)


func _push_shader_uniforms() -> void:
	if cam == null:
		return

	var mat := darkness.material as ShaderMaterial
	if mat == null:
		return

	mat.set_shader_parameter("enable_memory", GameConfig.fog_enable_memory)

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: Vector2 = cam.zoom

	var world_size: Vector2 = Vector2(vp_size.x / zoom.x, vp_size.y / zoom.y)
	var center_world: Vector2 = cam.get_screen_center_position()
	var top_left: Vector2 = center_world - world_size * 0.5

	mat.set_shader_parameter("cam_top_left_world", top_left)
	mat.set_shader_parameter("cam_size_world", world_size)
	mat.set_shader_parameter("maze_origin_world", maze_origin_world)
	mat.set_shader_parameter("maze_size_world", maze_size_world)


#region Private Methods (masks)
func _update_masks() -> void:
	if player == null or cam == null:
		return

	if suspended or _awaiting_level_start:
		vision_poly.polygon = PackedVector2Array()
		halo_poly.polygon = PackedVector2Array()
		return

	# CURRENT MASK (screen-space): cone + halo
	var origin_screen: Vector2 = _world_to_fog_local(player.global_position)

	var halo_radius_screen := GameConfig.fog_halo_world_radius * cam.zoom.x
	halo_poly.polygon = _make_circle(origin_screen, halo_radius_screen)

	var cone_screen := PackedVector2Array()
	cone_screen.append(origin_screen)

	var base: float = facing.angle()
	var half_angle_deg := GameConfig.fog_half_angle_deg
	var vision_range := GameConfig.fog_vision_range

	if _player_stats != null:
		half_angle_deg = _player_stats.get_fog_half_angle_deg(half_angle_deg)
		vision_range = _player_stats.get_fog_vision_range(vision_range)

	var half: float = deg_to_rad(half_angle_deg)

	for i in range(GameConfig.fog_rays):
		var t := 0.0 if GameConfig.fog_rays == 1 else float(i) / float(GameConfig.fog_rays - 1)
		var a: float = lerp(-half, half, t) + base
		var dir := Vector2(cos(a), sin(a))
		cone_screen.append(_cast_ray_to_screen(dir))

	vision_poly.polygon = cone_screen

	# EXPLORED MASK (memory): ONLY cone (no halo)
	if GameConfig.fog_enable_memory:
		var origin_exp: Vector2 = player.global_position - maze_origin_world

		# Occluded halo memory (does NOT see through walls)
		var halo_world_pts := _build_occluded_halo_world(
			player.global_position, GameConfig.fog_halo_world_radius, GameConfig.fog_halo_rays
		)

		var halo_exp := PackedVector2Array()
		for p in halo_world_pts:
			halo_exp.append(p - maze_origin_world)

		explored_halo.polygon = halo_exp

		var cone_exp := PackedVector2Array()
		cone_exp.append(origin_exp)

		for i in range(GameConfig.fog_rays):
			var t := 0.0 if GameConfig.fog_rays == 1 else float(i) / float(GameConfig.fog_rays - 1)
			var a: float = lerp(-half, half, t) + base
			var dir := Vector2(cos(a), sin(a))
			var end_world := _cast_ray_to_world(dir)
			cone_exp.append(end_world - maze_origin_world)

		explored_vision.polygon = cone_exp


func _cast_ray_to_world(dir: Vector2) -> Vector2:
	if player == null:
		return Vector2.ZERO

	var n_dir := dir
	if n_dir.length_squared() > 0.0:
		n_dir = n_dir.normalized()
	else:
		n_dir = Vector2.RIGHT

	var origin_world: Vector2 = player.global_position + n_dir * 6.0

	var vision_range := GameConfig.fog_vision_range
	if _player_stats != null:
		vision_range = _player_stats.get_fog_vision_range(vision_range)

	var to_world: Vector2 = origin_world + n_dir * vision_range
	var max_dist: float = origin_world.distance_to(to_world)

	# 1) Find first CLOSED door along the ray (doors are non-colliding, so physics won't hit them).
	var door_hit_world: Variant = _first_closed_door_hit_world(origin_world, n_dir, max_dist)

	# 2) Find first wall collider along the ray.
	var wall_hit_world: Variant = null

	var query := PhysicsRayQueryParameters2D.create(origin_world, to_world)
	query.collision_mask = wall_mask
	query.hit_from_inside = false
	query.exclude = [player]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var res := get_world_2d().direct_space_state.intersect_ray(query)
	if not res.is_empty():
		wall_hit_world = res.position

	# Choose the nearer occluder (closed doors block vision, walls still block too).
	var best_hit_world: Variant = null
	var best_dist: float = INF

	if door_hit_world != null:
		var d: float = origin_world.distance_to(door_hit_world)
		if d < best_dist:
			best_dist = d
			best_hit_world = door_hit_world

	if wall_hit_world != null:
		var d2: float = origin_world.distance_to(wall_hit_world)
		if d2 < best_dist:
			best_dist = d2
			best_hit_world = wall_hit_world

	if best_hit_world == null:
		return to_world

	# Nudge slightly *into* the hit surface so the blocking tile itself becomes visible.
	return best_hit_world + n_dir * HIT_INSET_PX


func _cast_ray_to_screen(dir: Vector2) -> Vector2:
	return _world_to_fog_local(_cast_ray_to_world(dir))


func _world_to_fog_local(world_pos: Vector2) -> Vector2:
	var screen_pos := get_viewport().get_canvas_transform() * world_pos
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _make_circle(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n: int = max(8, GameConfig.fog_halo_segments)
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


#region Private Methods (helpers)
func _wait_for_tiles() -> void:
	if layer == null:
		push_error("[FogOfWar._wait_for_tiles] layer is null")
		return

	for i in range(240):
		var used := layer.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			return
		await get_tree().process_frame
	push_warning("MazeLayer still empty after waiting; fog bounds will be wrong.")


func _clear_explored_once() -> void:
	# Godot doesn't expose a clear color on SubViewport, but transparent_bg = true
	# means CLEAR_MODE_ALWAYS will clear to transparent black.
	explored_viewport.transparent_bg = true

	explored_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	for _i in range(4):
		await get_tree().process_frame
	explored_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER


func _build_occluded_halo_world(
	origin_world: Vector2, radius: float, n_rays: int
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n_rays):
		var a := TAU * float(i) / float(n_rays)
		var dir := Vector2(cos(a), sin(a))
		var n_dir := dir
		if n_dir.length_squared() > 0.0:
			n_dir = n_dir.normalized()
		else:
			n_dir = Vector2.RIGHT

		var from := origin_world + n_dir * 2.0
		var to := origin_world + n_dir * radius
		var max_dist: float = from.distance_to(to)

		var door_hit_world: Variant = _first_closed_door_hit_world(from, n_dir, max_dist)

		var query := PhysicsRayQueryParameters2D.create(from, to)
		query.collision_mask = wall_mask
		query.hit_from_inside = false
		query.exclude = [player]
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var res := get_world_2d().direct_space_state.intersect_ray(query)
		var wall_hit_world: Variant = null
		if not res.is_empty():
			wall_hit_world = res.position

		var best_hit_world: Variant = null
		var best_dist: float = INF

		if door_hit_world != null:
			var d: float = from.distance_to(door_hit_world)
			if d < best_dist:
				best_dist = d
				best_hit_world = door_hit_world

		if wall_hit_world != null:
			var d2: float = from.distance_to(wall_hit_world)
			if d2 < best_dist:
				best_dist = d2
				best_hit_world = wall_hit_world

		var hit_pos: Vector2 = to
		if best_hit_world != null:
			hit_pos = best_hit_world + n_dir * HIT_INSET_PX

		pts.append(hit_pos)
	return pts


func _first_closed_door_hit_world(from_world: Vector2, dir: Vector2, max_dist: float) -> Variant:
	if layer == null:
		return null
	if not layer.has_method("is_door_closed"):
		return null

	var step: float = 4.0
	if tile_size.x > 0.0 and tile_size.y > 0.0:
		step = max(DOOR_STEP_MIN_PX, min(tile_size.x, tile_size.y) * DOOR_STEP_FRACTION_OF_TILE)
	else:
		step = max(DOOR_STEP_MIN_PX, 4.0)

	var traveled: float = 0.0
	var last_cell: Vector2i = Vector2i(2147483647, 2147483647)

	while traveled <= max_dist:
		var p_world: Vector2 = from_world + dir * traveled
		var p_local: Vector2 = layer.to_local(p_world)
		var cell: Vector2i = layer.local_to_map(p_local)
		if cell != last_cell:
			last_cell = cell
			if bool(layer.call("is_door_closed", cell)):
				# Return the first point that enters the closed door cell.
				return p_world
		traveled += step

	return null


#region Public Methods (level / save)
func reset_fog_for_level() -> void:
	await _wait_for_tiles()
	_compute_layer_bounds()
	_setup_viewports()
	await _clear_explored_once()

	# Also clear the polygons so you don't stamp a frame of junk
	explored_vision.polygon = PackedVector2Array()
	explored_halo.polygon = PackedVector2Array()
	vision_poly.polygon = PackedVector2Array()
	halo_poly.polygon = PackedVector2Array()

	# Clear any restored base texture for the new level
	if _explored_base != null:
		_explored_base.texture = null


func save_explored_to_file(path: String) -> Vector2i:
	if explored_viewport == null:
		return Vector2i.ZERO
	var tex := explored_viewport.get_texture()
	if tex == null:
		return Vector2i.ZERO
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Vector2i.ZERO
	var err := img.save_png(path)
	if err != OK:
		push_warning("[FogOfWarRW] Failed to save explored fog: %s" % path)
		return Vector2i.ZERO
	return Vector2i(img.get_width(), img.get_height())


func load_explored_from_file(path: String, expected_size: Vector2i = Vector2i.ZERO) -> bool:
	if path == "":
		return false
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_warning("[FogOfWarRW] Failed to load explored fog: %s" % path)
		return false
	if expected_size != Vector2i.ZERO:
		if img.get_width() != expected_size.x or img.get_height() != expected_size.y:
			push_warning("[FogOfWarRW] Explored fog size mismatch; ignoring save")
			return false
	_ensure_explored_base()
	_explored_base.texture = ImageTexture.create_from_image(img)
	return true
#endregion

#region Private Methods (explored base / resume)
func _ensure_explored_base() -> void:
	if _explored_base != null and is_instance_valid(_explored_base):
		return
	var root := explored_viewport.get_node_or_null("MaskRoot") as Node2D
	if root == null:
		return
	var existing := root.get_node_or_null("ExploredBase") as Sprite2D
	if existing != null:
		_explored_base = existing
		_explored_base.centered = false
		_explored_base.position = Vector2.ZERO
		_explored_base.z_index = -10
		return
	_explored_base = Sprite2D.new()
	_explored_base.name = "ExploredBase"
	_explored_base.centered = false
	_explored_base.position = Vector2.ZERO
	_explored_base.z_index = -10
	root.add_child(_explored_base)


func _resume_after_level_start() -> void:
	if not _pending_reveal:
		return

	# Wait for tiles + a couple frames so collisions and viewports are stable.
	await _wait_for_tiles()
	await get_tree().process_frame
	await get_tree().process_frame

	if _awaiting_level_start:
		return

	suspended = false
	_pending_reveal = false
	reveal_now()
#endregion
