extends Node
class_name VisionController
## Centralized vision and FOV system
## Owns: real-time FOV rendering, facing direction, explored memory, pressure calculations

# References
var player: Node2D
var camera: Camera2D
var fog: FogOfWarRW
var presence: Node2D

# Vision state
var facing: Vector2 = Vector2.RIGHT
var suspended: bool = false

func _ready() -> void:
	# Normally initialized by game.gd or caller
	pass

## Initialize with all required references
func initialize(p_player: Node2D, p_camera: Camera2D, p_fog: FogOfWarRW, p_presence: Node2D = null) -> bool:
	player = p_player
	camera = p_camera
	fog = p_fog
	presence = p_presence
	
	if player == null or camera == null or fog == null:
		push_error("[VisionController] Missing required references")
		return false
	
	# Initialize facing from player if available
	if "facing" in player:
		facing = player.facing
	
	print("[VisionController] Initialized successfully")
	return true

## Update player facing direction (called by player.gd)
func update_facing(new_facing: Vector2i) -> void:
	if new_facing == Vector2i.ZERO:
		return
	
	facing = Vector2(new_facing.x, new_facing.y)
	
	if fog != null and fog.has_method("set_facing_cardinal"):
		fog.set_facing_cardinal(facing)

## Update vision immediately (called after player moves)
func reveal_now() -> void:
	if fog != null and fog.has_method("reveal_now"):
		fog.reveal_now()

## Suspend vision (close eyes mechanic)
func suspend_vision(v: bool) -> void:
	suspended = v
	if fog != null and fog.has_method("set_suspended"):
		fog.set_suspended(v)

## Get pressure value (0.0-1.0) based on proximity to presence
func get_pressure01() -> float:
	if presence == null or not presence.has_method("get_pressure01"):
		return 0.0
	
	return clampf(float(presence.call("get_pressure01")), 0.0, 1.0)

## Reset fog for new level
func reset_for_level() -> void:
	if fog != null and fog.has_method("reset_fog_for_level"):
		fog.reset_fog_for_level()

## Rebuild fog for new maze
func rebuild_for_maze() -> void:
	if fog != null and fog.has_method("rebuild_for_current_maze"):
		fog.rebuild_for_current_maze()

## Get current player cell position
func get_player_cell() -> Vector2i:
	if player == null or not "cell" in player:
		return Vector2i.ZERO
	return player.cell as Vector2i

## Get facing as cardinal direction string
func get_facing_name() -> String:
	if abs(facing.x) > abs(facing.y):
		return "LEFT" if facing.x < 0 else "RIGHT"
	else:
		return "UP" if facing.y < 0 else "DOWN"
