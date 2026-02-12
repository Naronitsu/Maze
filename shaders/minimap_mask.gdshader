shader_type canvas_item;

// Base map texture (floors and walls)
uniform sampler2D base_map : hint_default_black;

// Explored texture from fog of war
uniform sampler2D explored_mask : hint_default_black;

// Colors for unexplored areas
uniform vec4 unexplored_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// Threshold for considering a pixel "explored"
uniform float explored_threshold : hint_range(0.0, 1.0) = 0.1;

void fragment() {
	// Sample the base map color
	vec4 base = texture(base_map, UV);
	
	// Sample the explored mask
	vec4 explored = texture(explored_mask, UV);
	
	// Check if this area has been explored
	float explored_amount = explored.r; // Use red channel as mask
	
	// If not explored, show unexplored color
	if (explored_amount < explored_threshold) {
		COLOR = unexplored_color;
	} else {
		// Show the base map
		COLOR = base;
	}
}
