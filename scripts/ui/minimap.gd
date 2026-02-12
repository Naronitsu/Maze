## Minimap UI that shows explored areas of the maze.
##
## Displays a top-down view of the dungeon scaled to fit in the corner.
## Only shows areas that have been explored using the fog of war explored texture.
extends Control
class_name Minimap

@export_category("Dependencies")
@export var layer: TileMapLayer
@export var fog: FogOfWarRW
@export var player: Node2D

@export_category("Configuration")
@export var minimap_size: Vector2 = Vector2(200, 200)
@export var border_padding: float = 10.0
@export var floor_color: Color = Color(0.9, 0.9, 0.9, 1.0)  # Light gray for walkable areas
@export var wall_color: Color = Color(0.0, 0.0, 0.0, 1.0)  # Black for walls
@export var door_closed_color: Color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow for closed doors
@export var door_open_color: Color = Color(1.0, 1.0, 1.0, 1.0)  # White for open doors
@export var player_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var unexplored_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var update_interval: float = 0.5  # Update every 0.5 seconds

var _map_texture: ImageTexture
var _maze_bounds: Rect2i
var _cell_size: Vector2  # Size of each cell in the minimap
var _update_timer: float = 0.0
var _shader_material: ShaderMaterial

@onready var map_display: TextureRect = $MapDisplay
@onready var player_marker: Control = $PlayerMarker

func _ready() -> void:
	# Check if minimap is enabled
	if not GameConfig.minimap_enabled:
		print("[Minimap] Disabled in GameConfig")
		visible = false
		set_process(false)
		return
	
	print("[Minimap] Initializing...")
	
	# Use config values if exports are at defaults
	if minimap_size == Vector2(200, 200):
		minimap_size = GameConfig.minimap_size
	if border_padding == 10.0:
		border_padding = GameConfig.minimap_border_padding
	if update_interval == 0.5:
		update_interval = GameConfig.minimap_update_interval
	
	# Validate references
	if layer == null:
		layer = get_node_or_null("../../TileMap/MazeLayer") as TileMapLayer
		if layer == null:
			push_error("[Minimap] TileMapLayer reference not found")
			return
	
	if fog == null:
		fog = get_node_or_null("../../Overlay/FogOfWarRW") as FogOfWarRW
		if fog == null:
			push_error("[Minimap] FogOfWar reference not found")
			return
	
	if player == null:
		player = get_node_or_null("../../Player") as Node2D
		if player == null:
			push_error("[Minimap] Player reference not found")
			return
	
	print("[Minimap] References validated: layer=%s, fog=%s, player=%s" % [layer != null, fog != null, player != null])
	
	# Position in top right corner - use simple position+size instead of anchors
	position = Vector2(get_viewport_rect().size.x - minimap_size.x - border_padding, border_padding)
	size = minimap_size
	custom_minimum_size = minimap_size
	clip_contents = false  # Don't clip player marker
	
	# Setup map display - don't override size, let anchors handle it
	map_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Setup player marker
	player_marker.custom_minimum_size = Vector2(6, 6)
	player_marker.size = Vector2(6, 6)
	player_marker.z_index = 200  # Ensure it's on top of everything
	
	# If it's a ColorRect, set color directly
	if player_marker is ColorRect:
		(player_marker as ColorRect).color = player_color
	
	# Setup shader for masking
	_setup_shader()
	
	# Wait for level to be ready
	EventBus.level_started.connect(_on_level_started)
	EventBus.player_moved.connect(_on_player_moved)
	
	# Listen for door events to update minimap
	if layer and layer.has_signal("door_opened"):
		layer.door_opened.connect(_on_door_opened)
	
	# Don't initialize yet - wait for level_started signal
	# _initialize_minimap()
	
	# Force visibility
	visible = true
	modulate = Color(1, 1, 1, 1)
	
	print("[Minimap] Ready complete, visible=%s, size=%s, position=%s" % [visible, size, position])
	print("[Minimap] Waiting for level_started signal to initialize map...")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"):  # Tab key
		visible = !visible
		get_viewport().set_input_as_handled()
		print("[Minimap] Toggled visibility: %s" % visible)

func _setup_shader() -> void:
	_shader_material = ShaderMaterial.new()
	var shader := load("res://shaders/minimap_mask.gdshader") as Shader
	if shader == null:
		push_error("[Minimap] Failed to load minimap shader")
		return
	
	_shader_material.shader = shader
	_shader_material.set_shader_parameter("unexplored_color", unexplored_color)
	_shader_material.set_shader_parameter("explored_threshold", 0.1)
	map_display.material = _shader_material
	print("[Minimap] Shader setup complete")

func _initialize_minimap() -> void:
	if layer == null:
		push_error("[Minimap] Cannot initialize - layer is null")
		return
	
	# Disconnect old door signal if connected
	if layer and layer.has_signal("door_opened"):
		if layer.door_opened.is_connected(_on_door_opened):
			layer.door_opened.disconnect(_on_door_opened)
	
	# Reset cell size
	_cell_size = Vector2.ZERO
	
	# Get maze bounds
	_maze_bounds = layer.get_used_rect()
	
	if _maze_bounds.size.x == 0 or _maze_bounds.size.y == 0:
		push_warning("[Minimap] Maze bounds are empty, waiting for level start")
		return
	
	print("[Minimap] Maze bounds: %s" % [_maze_bounds])
	
	# Calculate cell size for minimap (how many pixels per maze cell)
	# Account for 2px border on each side
	var available_size := minimap_size - Vector2(4, 4)
	var aspect_ratio := float(_maze_bounds.size.x) / float(_maze_bounds.size.y)
	
	if aspect_ratio > 1.0:
		# Wider than tall
		_cell_size.x = available_size.x / float(_maze_bounds.size.x)
		_cell_size.y = _cell_size.x
	else:
		# Taller than wide
		_cell_size.y = available_size.y / float(_maze_bounds.size.y)
		_cell_size.x = _cell_size.y
	
	# Create initial map texture (static, doesn't change)
	_render_static_map()
	
	# Update shader with explored texture
	_update_explored_mask()
	
	# Make sure player marker is visible
	player_marker.visible = true
	
	# Connect to door opened signal
	if layer and layer.has_signal("door_opened"):
		if not layer.door_opened.is_connected(_on_door_opened):
			layer.door_opened.connect(_on_door_opened)
	
	print("[Minimap] Initialization complete, cell_size=%s, marker visible=%s" % [_cell_size, player_marker.visible])

func _render_static_map() -> void:
	if layer == null or _maze_bounds.size.x == 0 or _maze_bounds.size.y == 0:
		push_warning("[Minimap] Cannot render - invalid bounds or no layer")
		return
	
	var map_pixel_width := int(_maze_bounds.size.x * _cell_size.x)
	var map_pixel_height := int(_maze_bounds.size.y * _cell_size.y)
	
	if map_pixel_width <= 0 or map_pixel_height <= 0:
		push_warning("[Minimap] Invalid pixel dimensions: %dx%d" % [map_pixel_width, map_pixel_height])
		return
	
	print("[Minimap] Rendering %dx%d map" % [map_pixel_width, map_pixel_height])
	
	var img := Image.create(map_pixel_width, map_pixel_height, false, Image.FORMAT_RGBA8)
	
	# Fill with wall color first
	img.fill(wall_color)
	
	print("[Minimap] Starting cell iteration, bounds: %s" % [_maze_bounds])
	var floor_count := 0
	var wall_count := 0
	
	# Render each cell of the maze (static map, doesn't depend on exploration)
	for y in range(_maze_bounds.size.y):
		for x in range(_maze_bounds.size.x):
			var cell := Vector2i(_maze_bounds.position.x + x, _maze_bounds.position.y + y)
			
			# Check if it's a door first
			var is_door := false
			var door_color := door_closed_color
			if layer.has_method("is_door_cell"):
				is_door = layer.call("is_door_cell", cell)
				if is_door:
					if layer.has_method("is_door_open") and layer.call("is_door_open", cell):
						door_color = door_open_color
			
			# Use the maze's is_floor method which checks the logical grid model
			var is_floor: bool = layer.is_floor(cell)
			
			if is_floor or is_door:
				floor_count += 1
			else:
				wall_count += 1
			
			# Only draw floor and door cells (walls are already the background)
			if not is_floor and not is_door:
				continue
			
			# Calculate exact pixel bounds for this cell to avoid gaps
			var pixel_x_start := int(floor(x * _cell_size.x))
			var pixel_y_start := int(floor(y * _cell_size.y))
			var pixel_x_end := int(floor((x + 1) * _cell_size.x))
			var pixel_y_end := int(floor((y + 1) * _cell_size.y))
			
			# Choose color based on cell type
			var cell_color := door_color if is_door else floor_color
			
			# Fill the cell rectangle
			for py in range(pixel_y_start, pixel_y_end):
				for px in range(pixel_x_start, pixel_x_end):
					if px < map_pixel_width and py < map_pixel_height:
						img.set_pixel(px, py, cell_color)
	
	print("[Minimap] Cell counts - floors: %d, walls: %d" % [floor_count, wall_count])
	print("[Minimap] Floor color: %s, Wall color: %s" % [floor_color, wall_color])
	
	# Always create a new texture (dimensions may have changed between levels)
	_map_texture = ImageTexture.create_from_image(img)
	
	map_display.texture = _map_texture
	
	print("[Minimap] Static map rendered, texture size: %s, has texture: %s" % [img.get_size(), map_display.texture != null])
	
	# Set shader parameter
	if _shader_material != null:
		_shader_material.set_shader_parameter("base_map", _map_texture)

func _update_explored_mask() -> void:
	if fog == null or fog.explored_viewport == null:
		push_warning("[Minimap] Cannot update mask - fog or viewport is null")
		return
	
	var explored_tex := fog.explored_viewport.get_texture()
	if explored_tex == null:
		push_warning("[Minimap] Explored texture is null")
		return
	
	# Set the explored texture as the mask in the shader
	if _shader_material != null:
		_shader_material.set_shader_parameter("explored_mask", explored_tex)

func _process(delta: float) -> void:
	_update_timer += delta
	
	# Update explored mask periodically
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_explored_mask()
	
	# Update player marker position every frame
	_update_player_marker()

func _update_player_marker() -> void:
	if player == null or layer == null:
		return
	
	# Don't update until maze bounds are initialized
	if _maze_bounds.size.x == 0 or _maze_bounds.size.y == 0:
		return
	
	# Get player's cell position
	var player_world_pos := player.global_position
	var player_cell := layer.local_to_map(layer.to_local(player_world_pos))
	
	# Convert to minimap coordinates
	var relative_x := float(player_cell.x - _maze_bounds.position.x) / float(_maze_bounds.size.x)
	var relative_y := float(player_cell.y - _maze_bounds.position.y) / float(_maze_bounds.size.y)
	
	# Calculate actual rendered map size (not minimap_size, which is the full control size)
	var actual_map_width := _maze_bounds.size.x * _cell_size.x
	var actual_map_height := _maze_bounds.size.y * _cell_size.y
	
	# Position marker within the actual map, accounting for 2px border
	var border_offset := 2.0
	var marker_x := border_offset + relative_x * actual_map_width - 3.0  # Center 6px marker
	var marker_y := border_offset + relative_y * actual_map_height - 3.0
	
	# Use offsets for Control nodes with layout_mode = 0
	player_marker.set_position(Vector2(marker_x, marker_y))
	player_marker.set_size(Vector2(6, 6))
	player_marker.visible = true
	player_marker.modulate = Color(1, 0, 0, 1)  # Force red color

func _on_level_started(_spawn_cell: Vector2i, _maze: DungeonMazeLayer) -> void:
	# Reinitialize when level starts
	print("[Minimap] Level started signal received, waiting 0.5s for fog...")
	await get_tree().create_timer(0.5).timeout  # Wait for fog to be ready
	print("[Minimap] Initializing minimap now...")
	_initialize_minimap()

func _on_player_moved(_from: Vector2i, _to: Vector2i) -> void:
	# Player marker updates every frame in _process, no need to do anything here
	pass

func _on_door_opened(cell: Vector2i) -> void:
	# Update the single door cell from yellow to white
	if _map_texture == null or _maze_bounds.size.x == 0:
		return
	
	# Calculate local coordinates
	var local_x := cell.x - _maze_bounds.position.x
	var local_y := cell.y - _maze_bounds.position.y
	
	if local_x < 0 or local_x >= _maze_bounds.size.x or local_y < 0 or local_y >= _maze_bounds.size.y:
		return
	
	# Calculate pixel bounds
	var pixel_x_start := int(floor(local_x * _cell_size.x))
	var pixel_y_start := int(floor(local_y * _cell_size.y))
	var pixel_x_end := int(floor((local_x + 1) * _cell_size.x))
	var pixel_y_end := int(floor((local_y + 1) * _cell_size.y))
	
	# Update the image
	var img := _map_texture.get_image()
	for py in range(pixel_y_start, pixel_y_end):
		for px in range(pixel_x_start, pixel_x_end):
			if px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, door_open_color)
	
	# Update texture
	_map_texture.update(img)
	print("[Minimap] Door opened at %s, updated to white" % cell)
