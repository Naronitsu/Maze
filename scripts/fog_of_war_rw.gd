extends Control
class_name FogOfWarRW

@export var player_path: NodePath
@export var camera_path: NodePath

@export var wall_mask: int = 1 << 0
@export var layer_path: NodePath
@export var show_mask_preview: bool = false

@onready var player: Node2D = get_node(player_path)
@onready var cam: Camera2D = get_node(camera_path) as Camera2D
@onready var layer: TileMapLayer = get_node(layer_path)

# Current (screen-sized) mask viewport
@onready var viewport: SubViewport = $MaskViewport
@onready var vision_poly: Polygon2D = $MaskViewport/MaskRoot/VisionMask
@onready var halo_poly: Polygon2D = $MaskViewport/MaskRoot/HaloMask

# Explored (world-sized) mask viewport
@onready var explored_viewport: SubViewport = $ExploredViewport
@onready var explored_vision: Polygon2D = $ExploredViewport/MaskRoot/VisionMask
@onready var explored_halo: Polygon2D = $ExploredViewport/MaskRoot/HaloMask

@onready var darkness: ColorRect = $Darkness
@onready var mask_preview: TextureRect = get_node_or_null("MaskPreview") as TextureRect

var facing: Vector2 = Vector2.RIGHT
var suspended: bool = false
var _awaiting_level_start: bool = true
var _pending_reveal: bool = false
var _explored_base: Sprite2D

var maze_origin_world: Vector2
var maze_size_world: Vector2
var tile_size: Vector2

const MASK_LAYER_BIT := 19
const MASK_LAYER := 1 << MASK_LAYER_BIT

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Keep fog frozen until the level is fully ready.
	suspended = true
	_awaiting_level_start = true
	EventBus.level_started.connect(_on_level_started)
	EventBus.level_transitioning.connect(_on_level_transitioning)

	await _wait_for_tiles()

	_compute_layer_bounds()
	_setup_viewports()
	_setup_darkness_shader()
	_ensure_explored_base()

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

func _on_level_started(_spawn_cell: Vector2i, _maze: DungeonMazeLayer) -> void:
	_awaiting_level_start = false
	_pending_reveal = true
	_resume_after_level_start()

func _on_level_transitioning() -> void:
	suspended = true
	_awaiting_level_start = true
	_pending_reveal = false

func _process(_dt: float) -> void:
	_push_shader_uniforms()
	_update_masks()

func set_facing_cardinal(dir) -> void:
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

# -------------------------
# Bounds + viewports
# -------------------------

func _compute_layer_bounds() -> void:
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

# -------------------------
# Masks
# -------------------------

func _update_masks() -> void:
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
	var half: float = deg_to_rad(GameConfig.fog_half_angle_deg)

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
		var halo_world_pts := _build_occluded_halo_world(player.global_position, GameConfig.fog_halo_world_radius, GameConfig.fog_halo_rays)

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
	var origin_world: Vector2 = player.global_position + dir * 6.0
	var to_world: Vector2 = origin_world + dir * GameConfig.fog_vision_range

	var query := PhysicsRayQueryParameters2D.create(origin_world, to_world)
	query.collision_mask = wall_mask
	query.hit_from_inside = false
	query.exclude = [player]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var res := get_world_2d().direct_space_state.intersect_ray(query)
	if res.is_empty():
		return to_world
	return res.position - dir * 2.0

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

# -------------------------
# Helpers
# -------------------------

func _wait_for_tiles() -> void:
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

func _build_occluded_halo_world(origin_world: Vector2, radius: float, n_rays: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n_rays):
		var a := TAU * float(i) / float(n_rays)
		var dir := Vector2(cos(a), sin(a))

		var from := origin_world + dir * 2.0
		var to := origin_world + dir * radius

		var query := PhysicsRayQueryParameters2D.create(from, to)
		query.collision_mask = wall_mask
		query.hit_from_inside = false
		query.exclude = [player]
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var res := get_world_2d().direct_space_state.intersect_ray(query)
		var hit_pos: Vector2 = to
		if not res.is_empty():
			hit_pos = res.position - dir * 2.0

		pts.append(hit_pos)
	return pts
	
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
