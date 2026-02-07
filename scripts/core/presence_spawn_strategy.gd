extends Node
class_name PresenceSpawnStrategy
## Base strategy for presence spawning logic
## Override attempt() to implement different spawn strategies

var controller: GameController
var maze: DungeonMazeLayer

func _init(p_controller: GameController, p_maze: DungeonMazeLayer) -> void:
	controller = p_controller
	maze = p_maze

## Try to spawn at given cell. Returns true if successful.
func attempt(presence_node: PresenceRW) -> bool:
	return false

# ============================================================
# Strategy: Spawn from player history (at level entrance)
# ============================================================
class HistoryStrategy extends PresenceSpawnStrategy:
	func attempt(presence_node: PresenceRW) -> bool:
		if controller == null or controller.player_history.is_empty():
			return false
		
		var spawn_cell: Vector2i = controller.player_history[0]
		
		# Verify passable
		if not _is_passable(spawn_cell):
			# Try neighbors
			for neighbor in controller.get_neighbors4(spawn_cell):
				if _is_passable(neighbor):
					spawn_cell = neighbor
					break
		else:
			return false
		
		# Spawn presence at history start
		presence_node.cell = spawn_cell
		presence_node.global_position = controller.cell_to_world_center(spawn_cell)
		
		return true
	
	func _is_passable(cell: Vector2i) -> bool:
		if maze == null:
			return false
		return maze.is_floor(cell)

# ============================================================
# Strategy: Spawn at maze spawn point (room entrance)
# ============================================================
class RoomSpawnStrategy extends PresenceSpawnStrategy:
	func attempt(presence_node: PresenceRW) -> bool:
		if maze == null or controller == null:
			return false
		
		var spawn_cell: Vector2i = maze.get_spawn_cell()
		
		if spawn_cell == Vector2i(-999999, -999999):
			return false
		
		# Verify passable
		if not maze.is_floor(spawn_cell):
			return false
		
		# Spawn presence at history start
		presence_node.cell = spawn_cell
		presence_node.global_position = controller.cell_to_world_center(spawn_cell)
		
		return true

# ============================================================
# Strategy: Spawn far from player (random distance)
# ============================================================
class FarSpawnStrategy extends PresenceSpawnStrategy:
	var min_distance: int = 18
	var max_attempts: int = 800
	
	func _init(p_controller: GameController, p_maze: DungeonMazeLayer, p_min_dist: int = 18, p_attempts: int = 800) -> void:
		super._init(p_controller, p_maze)
		min_distance = p_min_dist
		max_attempts = p_attempts
	
	func attempt(presence_node: PresenceRW) -> bool:
		if controller == null or controller.player == null or maze == null:
			return false
		
		var player_cell: Vector2i = controller.world_to_cell(controller.player.global_position)
		var size: Vector2i = controller.grid_size_cells()
		
		if size == Vector2i.ZERO:
			return false
		
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		
		for attempt in range(max_attempts):
			var rand_cell: Vector2i = Vector2i(
				rng.randi_range(0, size.x - 1),
				rng.randi_range(0, size.y - 1)
			)
			
			# Must be floor
			if not maze.is_floor(rand_cell):
				continue
			
			# Must be far enough
			var dist: int = controller.path_distance(player_cell, rand_cell)
			if dist < min_distance:
				continue
			
			# Success!
			presence_node.cell = rand_cell
			presence_node.global_position = controller.cell_to_world_center(rand_cell)
			
			return true
		
		return false
