shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Force mask sampling to be stable (prevents 1px seams from filtering/jitter)
uniform sampler2D current_tex : filter_nearest;
uniform sampler2D explored_tex : filter_nearest;

uniform float darkness_alpha = 1.0;
uniform float explored_strength = 0.55; // 0 = none, 1 = very dark memory

uniform vec2 cam_top_left_world;
uniform vec2 cam_size_world;
uniform vec2 maze_origin_world;
uniform vec2 maze_size_world;

uniform bool enable_memory = true;

void fragment() {
	vec4 base = texture(SCREEN_TEXTURE, SCREEN_UV);

	float cur = texture(current_tex, UV).r;

	float exp = 0.0;
	if (enable_memory) {
		vec2 world_pos = cam_top_left_world + UV * cam_size_world;
		vec2 euv_raw = (world_pos - maze_origin_world) / maze_size_world;

		// Tiny epsilon to avoid precision seams, but don't smear edges
		float eps = 1.5 / max(maze_size_world.x, maze_size_world.y);

		bool in_bounds =
			(euv_raw.x >= -eps && euv_raw.x <= 1.0 + eps &&
			 euv_raw.y >= -eps && euv_raw.y <= 1.0 + eps);

		if (in_bounds) {
			vec2 euv = clamp(euv_raw, vec2(0.0), vec2(1.0));

			// Sample at texel centers to avoid boundary jitter
			vec2 texel = 1.0 / vec2(textureSize(explored_tex, 0));
			euv = euv * (1.0 - texel) + texel * 0.5;

			exp = texture(explored_tex, euv).r;
		}

		// Current visibility counts as explored
		exp = max(exp, cur);
	}

	vec4 out_col = vec4(0.0);

	// Unseen = black overlay
	if (cur <= 0.0 && exp <= 0.0) {
		out_col = vec4(0.0, 0.0, 0.0, darkness_alpha);

	// Visible now = no overlay
	} else if (cur > 0.0) {
		out_col = vec4(0.0, 0.0, 0.0, 0.0);

	// Explored memory = darken underlying image
	} else {
		float m = 1.0 - explored_strength;
		vec3 darkened = base.rgb * m;

		// Difference-as-overlay darkening
		vec3 diff = base.rgb - darkened;

		out_col = vec4(diff, 1.0);
	}

	COLOR = out_col;
}
