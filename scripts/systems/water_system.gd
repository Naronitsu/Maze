extends Node2D

const INVALID_CELL := Vector2i(-999999, -999999)
const WATER_DROPLET_SCENE := preload("res://scenes/particles/water_droplet.tscn")
const WATER_DROP_PARTICLE_SCENE := preload("res://scenes/particles/water_drop_particle.tscn")
const BUCKET_SCENE := preload("res://scenes/particles/bucket.tscn")
const BUCKET_WATER_SCALE_MULT := 1.4
const WATER_FADE_START_AMOUNT := 0.05
const WATER_BUCKET_MIN_ALPHA := 0.6
const WATER_SPRITE_MAX_AMOUNT := 1.2
const WATER_PRESENCE_ON_MULT := 100.0

var bucket_amount: float = 0.0
var bucket_cell: Vector2i = INVALID_CELL
var bucket_placed: bool = false
var bucket_node: Node2D = null

var water_cells: Dictionary = {} # Vector2i -> WaterDroplet

var controller: GameController = null
var player: CharacterBody2D = null
var presence: PresenceRW = null

var _accum: float = 0.0
var _game_over_emitted: bool = false
var _last_drop_cell: Vector2i = INVALID_CELL
var _drop_spawn_timer: float = 0.0

func _ready() -> void:
	print("========== WaterSystem._ready() CALLED ==========")
	z_index = 0  # Same level as tilemap, below player
	bucket_amount = clampf(GameConfig.water_bucket_start_amount, 0.0, GameConfig.water_bucket_capacity)
	print("[WaterSystem] Ready. Bucket amount: %.2f (z_index: %d)" % [bucket_amount, z_index])
	print("[WaterSystem] Parent: %s, Owner: %s" % [get_parent().name if get_parent() else "NONE", owner.name if owner else "NONE"])
	EventBus.level_started.connect(_on_level_started)
	call_deferred("_resolve_refs")
	set_process(true)
	print("========== WaterSystem._ready() COMPLETE ==========")

func set_refs(p_controller: GameController, p_player: CharacterBody2D, p_presence: PresenceRW) -> void:
	controller = p_controller
	player = p_player
	presence = p_presence

func _process(delta: float) -> void:
	if GameState.current != GameState.State.PLAYING:
		return

	_resolve_refs()
	if controller == null or player == null:
		return

	if Input.is_action_just_pressed(GameConfig.player_place_bucket_action):
		_toggle_bucket_placement()

	_sync_bucket_node()

	_accum += delta
	if _accum < GameConfig.water_update_interval:
		return

	var step := _accum
	_accum = 0.0

	if not bucket_placed:
		bucket_cell = controller.world_to_cell(player.global_position)

	if bucket_cell == INVALID_CELL:
		return

	_drop_spawn_timer += step
	_evaporate_water(step)
	_apply_bucket_leak(step)

	if bucket_amount <= 0.0:
		bucket_amount = 0.0
		_on_bucket_empty()


func _apply_bucket_leak(step: float) -> void:
	if bucket_amount <= 0.0:
		return

	var leak_rate := GameConfig.water_bucket_leak_per_second
	var leak_mult := 1.0 + _presence_leak_bonus(bucket_cell)
	var leak := leak_rate * leak_mult * step
	if leak <= 0.0:
		return

	var actual := minf(leak, bucket_amount)
	bucket_amount -= actual

	var pool_cell := bucket_cell
	if not bucket_placed and controller != null and player != null:
		pool_cell = controller.world_to_cell(player.global_position)
	_add_water(pool_cell, actual)

	# Visual drop particles disabled for now
	# if _drop_spawn_timer >= 1.5:
	# 	_drop_spawn_timer = 0.0
	# 	var drop_pos := Vector2.ZERO
	# 	if bucket_placed and controller != null:
	# 		drop_pos = controller.cell_to_world_center(bucket_cell)
	# 	elif player != null:
	# 		drop_pos = player.global_position
	# 	_spawn_falling_drop(drop_pos)

func _evaporate_water(step: float) -> void:
	if water_cells.is_empty():
		return

	var evap_rate := GameConfig.water_puddle_evap_per_second
	var to_erase: Array[Vector2i] = []

	for c in water_cells.keys():
		# Defensive: stored reference may have been freed elsewhere
		var raw := water_cells[c] as WaterDroplet
		if raw == null or not is_instance_valid(raw):
			to_erase.append(c)
			continue
		var droplet := raw as WaterDroplet
		if droplet == null:
			to_erase.append(c)
			continue
		var amt: float = droplet.amount
		var mult := 1.0 + _presence_evap_bonus(c)
		if presence != null and presence.is_active():
			var p_cell := presence.cell
			if p_cell == INVALID_CELL:
				p_cell = controller.world_to_cell(presence.global_position)
			if p_cell == c:
				mult = maxf(mult, WATER_PRESENCE_ON_MULT)
		
		# Bucket pool water evaporates slower
		if c == bucket_cell and bucket_placed:
			mult *= GameConfig.water_bucket_pool_evap_mult  # 2x slower evaporation
		
		var evap_amount := evap_rate * mult * step
		amt -= evap_amount
		if amt <= 0.0:
			to_erase.append(c)
		else:
			droplet.amount = amt
			_update_water_visual(c, droplet, true)

	for c in to_erase:
		_remove_droplet(water_cells, c)

func _add_water(cell: Vector2i, amount: float) -> void:
	var droplet := _get_or_create_water(cell)
	if amount > 0.0:
		droplet.amount += amount
	_update_water_visual(cell, droplet, false)

func _presence_leak_bonus(cell: Vector2i) -> float:
	return _presence_bonus(cell, GameConfig.water_presence_leak_multiplier)

func _presence_evap_bonus(cell: Vector2i) -> float:
	return _presence_bonus(cell, GameConfig.water_presence_evap_multiplier)

func _presence_bonus(cell: Vector2i, multiplier: float) -> float:
	if multiplier <= 0.0:
		return 0.0
	if presence == null or not presence.is_active():
		return 0.0
	if cell == INVALID_CELL:
		return 0.0
	var p_cell := presence.cell
	if p_cell == INVALID_CELL:
		p_cell = controller.world_to_cell(presence.global_position)
	var d: int = abs(p_cell.x - cell.x) + abs(p_cell.y - cell.y)
	if d <= GameConfig.water_presence_radius_cells:
		return multiplier
	return 0.0

func get_preferred_target_cell() -> Vector2i:
	if not water_cells.is_empty():
		var best_cell := INVALID_CELL
		var best_amount := -1.0
		for c in water_cells.keys():
			var droplet := water_cells[c] as WaterDroplet
			var amt := droplet.amount
			if amt <= GameConfig.water_puddle_min_amount:
				continue
			if amt > best_amount:
				best_amount = amt
				best_cell = c
		if best_cell != INVALID_CELL:
			return best_cell

	if bucket_amount > 0.0:
		if not bucket_placed and player != null and controller != null:
			bucket_cell = controller.world_to_cell(player.global_position)
		return bucket_cell

	return INVALID_CELL

func has_water_at(cell: Vector2i) -> bool:
	if cell == INVALID_CELL:
		return false
	return water_cells.has(cell)

func _on_bucket_empty() -> void:
	if _game_over_emitted:
		return
	_game_over_emitted = true
	GameState.current = GameState.State.GAME_OVER
	EventBus.game_over.emit()

func _on_level_started(player_cell: Vector2i, _maze: Node) -> void:
	bucket_placed = false
	bucket_cell = player_cell
	_last_drop_cell = INVALID_CELL
	_game_over_emitted = false
	_drop_spawn_timer = 0.0
	_clear_droplets(water_cells)
	_remove_bucket_node()

func _resolve_refs() -> void:
	if controller == null and SceneReferences.controller != null:
		controller = SceneReferences.controller as GameController
	if player == null and SceneReferences.player != null:
		player = SceneReferences.player as CharacterBody2D
	if presence == null and SceneReferences.presence != null:
		presence = SceneReferences.presence as PresenceRW

func _toggle_bucket_placement() -> void:
	if controller == null or player == null:
		return

	var c := controller.world_to_cell(player.global_position)
	if not controller.is_walkable(c):
		return

	if bucket_placed:
		# Trying to pick up - check if close enough
		var dist_to_bucket: int = abs(c.x - bucket_cell.x) + abs(c.y - bucket_cell.y)
		if dist_to_bucket > GameConfig.water_bucket_pickup_distance:
			print("[WaterSystem] Too far from bucket (distance: %d)" % dist_to_bucket)
			return
		bucket_placed = false
		_remove_bucket_node()
	else:
		# Placing bucket
		bucket_placed = true
		bucket_cell = c
		_ensure_bucket_node()
		if water_cells.has(bucket_cell):
			_update_water_visual(bucket_cell, water_cells[bucket_cell] as WaterDroplet, false)

func _get_or_create_water(cell: Vector2i) -> WaterDroplet:
	if water_cells.has(cell):
		return water_cells[cell] as WaterDroplet
	return _get_or_create_droplet(water_cells, cell)

func _get_or_create_droplet(store: Dictionary, cell: Vector2i) -> WaterDroplet:
	if store.has(cell):
		return store[cell] as WaterDroplet
	var existing := _find_water_node_at_cell(cell)
	if existing != null:
		store[cell] = existing
		return existing
	var droplet := WATER_DROPLET_SCENE.instantiate() as WaterDroplet
	add_child(droplet)
	# z_index inherited from parent (WaterSystem)
	store[cell] = droplet
	if controller != null:
		droplet.global_position = controller.cell_to_world_center(cell)
	return droplet

func _remove_droplet(store: Dictionary, cell: Vector2i) -> void:
	if not store.has(cell):
		return
	var droplet := store[cell] as WaterDroplet
	store.erase(cell)
	if is_instance_valid(droplet):
		droplet.queue_free()

func _clear_droplets(store: Dictionary) -> void:
	for cell in store.keys():
		_remove_droplet(store, cell)
	store.clear()

func _find_water_node_at_cell(cell: Vector2i) -> WaterDroplet:
	if controller == null:
		return null
	var target_pos := controller.cell_to_world_center(cell)
	for child in get_children():
		var droplet := child as WaterDroplet
		if droplet == null:
			continue
		if droplet.global_position.distance_to(target_pos) <= 0.1:
			return droplet
	return null

func _update_water_visual(cell: Vector2i, droplet: WaterDroplet, use_evap_alpha: bool) -> void:
	var max_amount := maxf(GameConfig.water_puddle_alpha_max_amount, 0.001)
	var max_amount_local := max_amount
	if bucket_placed and cell == bucket_cell:
		max_amount_local = max_amount * 0.25
	var sprite_max_amount := WATER_SPRITE_MAX_AMOUNT
	if bucket_placed and cell == bucket_cell:
		sprite_max_amount = WATER_SPRITE_MAX_AMOUNT * 0.75
	var alpha := 1.0
	if use_evap_alpha:
		alpha = clampf(droplet.amount / WATER_FADE_START_AMOUNT, 0.0, 1.0)
		if bucket_placed and cell == bucket_cell and droplet.amount > 0.0:
			alpha = maxf(alpha, WATER_BUCKET_MIN_ALPHA)
	if controller != null:
		droplet.global_position = controller.cell_to_world_center(cell)
	var scale_mult := 1.0
	if bucket_placed and cell == bucket_cell:
		scale_mult = BUCKET_WATER_SCALE_MULT
	droplet.update_visuals(droplet.amount, sprite_max_amount, alpha, scale_mult)

func _ensure_bucket_node() -> void:
	if bucket_node != null:
		return
	bucket_node = BUCKET_SCENE.instantiate() as Node2D
	# z_index inherited from parent (WaterSystem)
	add_child(bucket_node)
	if controller != null:
		bucket_node.global_position = controller.cell_to_world_center(bucket_cell)

func _remove_bucket_node() -> void:
	if bucket_node == null:
		return
	if is_instance_valid(bucket_node):
		bucket_node.queue_free()
	bucket_node = null

func _sync_bucket_node() -> void:
	if not bucket_placed:
		return
	_ensure_bucket_node()
	if bucket_node != null and controller != null:
		bucket_node.global_position = controller.cell_to_world_center(bucket_cell)

func _spawn_falling_drop(world_pos: Vector2) -> void:
	if WATER_DROP_PARTICLE_SCENE == null:
		return
	if world_pos == Vector2.ZERO:
		return
	var drop := WATER_DROP_PARTICLE_SCENE.instantiate() as WaterDropParticle
	if drop == null:
		return
	add_child(drop)
	drop.spawn_falling(world_pos)
