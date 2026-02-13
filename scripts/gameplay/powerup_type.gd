extends Resource
class_name PowerupType

enum Type {
	VISION_BOOST,
	MOVE_SPEED,
	CHARGE_SPEED
}

@export var type: Type = Type.VISION_BOOST
@export var icon_region: Rect2
@export var description: String
@export var apply_func: Callable
