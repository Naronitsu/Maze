extends Node

## Centralized game configuration.
## All tuning variables in one place for easy balancing.

# Door transition tuning
var door_pause_time: float = 0.25
var door_fade_time: float = 0.20
var door_text_hold_time: float = 0.8
var door_message_time: float = 1.2
var door_message: String = "there is a monster behind you, run"

# Presence pacing / spawning
var presence_head_start_time: float = 2.5
var presence_min_spawn_dist_cells: int = 12
var presence_min_history_steps: int = 8
var presence_wait_history_max_seconds: float = 6.0

# Player movement
var player_step_time: float = 0.22
var player_sprite_scale: float = 0.75
var player_close_eyes_action: StringName = &"close_eyes"
var player_run_grace_time: float = 0.20
var player_interact_action: StringName = &"interact"
var player_trail_history_max: int = 80

# Game progression
var max_levels_before_reset: int = 10

# Maze generation
var maze_base_width: int = 40
var maze_base_height: int = 40
var maze_size_growth_per_level: int = 2
var maze_run_growth: float = 0.12

# Decorations (markings.png)
var markings_density_per_floor: float = 0.008
var markings_min_per_level: int = 30
var markings_max_per_level: int = 40
var markings_min_spacing_cells: int = 2
var markings_avoid_spawn_radius_cells: int = 2
var markings_avoid_exit_radius_cells: int = 2

# Pillar (room center interactable)
var pillar_charge_time_seconds: float = 12.0

# GameController tuning
var controller_trail_add_walk: float = 1.0
var controller_trail_add_run: float = 2.0
var controller_trail_decay_per_second: float = 0.8
var controller_trail_floor: float = 0.0
var controller_history_max: int = 250

# Presence AI
var presence_move_interval: float = 0.45
var presence_near_cells: int = 4
var presence_far_cells: int = 25
var presence_catch_distance_cells: int = -1

# FOV/Vision
var fog_vision_range: float = 64
var fog_half_angle_deg: float = 35.0
var fog_rays: int = 81
var fog_halo_rays: int = 64
var fog_halo_world_radius: float = 16
var fog_halo_segments: int = 24
var fog_darkness_alpha: float = 1.0
var fog_explored_alpha: float = 0.20
var fog_enable_memory: bool = true
var fog_memory_forget_rate_per_second: float = 0.1

# Heartbeat UI
var heartbeat_bpm_min: float = 48.0
var heartbeat_bpm_max: float = 140.0
var heartbeat_veins_alpha_min: float = 0.00
var heartbeat_veins_alpha_max: float = 0.55
var heartbeat_veins_base_alpha_max: float = 0.18
var heartbeat_veins_scale_min: float = 1.00
var heartbeat_veins_scale_max: float = 1.10
var heartbeat_dub_delay: float = 0.12
var heartbeat_beat_fade_in: float = 0.05
var heartbeat_beat_fade_out: float = 0.12
var heartbeat_cam_thump_zoom: float = 0.985
var heartbeat_cam_thump_in: float = 0.03
var heartbeat_cam_thump_out: float = 0.10

# Minimap
var minimap_enabled: bool = true
var minimap_size: Vector2 = Vector2(200, 200)
var minimap_border_padding: float = 10.0
var minimap_update_interval: float = 0.5

func _init() -> void:
	pass

func get_all_vars() -> Dictionary:
	"""Return all config variables as a dictionary for debugging/export."""
	var result = {}
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			result[property.name] = get(property.name)
	return result
