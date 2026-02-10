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
var player_place_bucket_action: StringName = &"place_bucket"

# Game progression
var max_levels_before_reset: int = 10

# Maze generation
var maze_base_width: int = 25
var maze_base_height: int = 25
var maze_size_growth_per_level: int = 2
var maze_run_growth: float = 0.12

# Decorations (markings.png)
var markings_density_per_floor: float = 0.008
var markings_min_per_level: int = 30
var markings_max_per_level: int = 40
var markings_min_spacing_cells: int = 2
var markings_avoid_spawn_radius_cells: int = 2
var markings_avoid_exit_radius_cells: int = 2

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

# Water system
var water_bucket_capacity: float = 100.0
var water_bucket_start_amount: float = 100.0
var water_bucket_leak_per_second: float = 0.4
var water_bucket_pickup_distance: int = 1  # Can only pick up bucket if within this distance
var water_puddle_evap_per_second: float = 0.005  # Very slow base evap when no presence (~3 min to empty)
var water_puddle_min_amount: float = 0.02
var water_bucket_pool_evap_mult: float = 0.5  # Pooled water at bucket evaporates 2x slower
var water_presence_radius_cells: int = 4  # Presence within 4 cells triggers fast evap
var water_presence_leak_multiplier: float = 1.0
var water_presence_evap_multiplier: float = 9.0  # 10x faster evap when presence near (not on top)
var water_drop_lifetime: float = 30.0  # Drops stay on ground for 30 seconds
var water_drop_evap_presence_radius: int = 3  # Drops evaporate faster if presence within 3 cells
var water_update_interval: float = 0.1
var water_puddle_radius_world: float = 6.0
var water_puddle_alpha_max: float = 0.7
var water_puddle_alpha_max_amount: float = 20.0
var water_bucket_marker_radius_world: float = 3.0

# FOV/Vision
var fog_vision_range: float = 64
var fog_half_angle_deg: float = 35.0
var fog_rays: int = 81
var fog_halo_rays: int = 64
var fog_halo_world_radius: float = 16
var fog_halo_segments: int = 24
var fog_darkness_alpha: float = 1.0
var fog_explored_alpha: float = 0.60
var fog_enable_memory: bool = true

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

func _init() -> void:
	pass

func get_all_vars() -> Dictionary:
	"""Return all config variables as a dictionary for debugging/export."""
	var result = {}
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			result[property.name] = get(property.name)
	return result
