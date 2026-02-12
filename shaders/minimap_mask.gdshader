shader_type canvas_item;

// Base map texture (floors and walls)
uniform sampler2D base_map;

// Explored texture from fog of war (viewport mask)
uniform sampler2D explored_mask;

// Colors for unexplored areas
uniform vec4 unexplored_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// Threshold for considering a pixel "explored"
uniform float explored_threshold : hint_range(0.0, 1.0) = 0.02;

// Zoom controls (used by UI minimap)
// zoom_enabled: 0 = off, 1 = on
uniform float zoom_enabled = 0.0;
// zoom: 1 = no zoom, >1 = zoom in
uniform float zoom = 1.0;
// zoom_center_uv: where the zoom is centered (player position in base_map UV)
uniform vec2 zoom_center_uv = vec2(0.5, 0.5);

void fragment() {
	float z_on = step(0.5, zoom_enabled) * step(1.0001, zoom);
	float z = max(zoom, 1.0);
	vec2 zoom_uv = (UV - vec2(0.5, 0.5)) / z + zoom_center_uv;
	vec2 sample_uv = mix(UV, zoom_uv, z_on);

	// In-bounds mask (1 if within [0,1], else 0)
	float in_bounds =
		step(0.0, sample_uv.x) * step(sample_uv.x, 1.0) *
		step(0.0, sample_uv.y) * step(sample_uv.y, 1.0);

	vec2 clamped_uv = clamp(sample_uv, vec2(0.0), vec2(1.0));

	vec4 base = texture(base_map, clamped_uv);
	vec4 explored = texture(explored_mask, clamped_uv);
	float explored_amount = max(explored.r, explored.a);

	float explored_ok = step(explored_threshold, explored_amount) * in_bounds;
	COLOR = mix(unexplored_color, base, explored_ok);
}
