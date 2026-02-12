shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Force mask sampling to be stable (prevents 1px seams from filtering/jitter)
uniform sampler2D current_tex : filter_nearest;
uniform sampler2D explored_tex : filter_nearest;

uniform float darkness_alpha = 1.0;
uniform float explored_alpha = 0.60; // explored-but-not-current darkness

uniform vec2 cam_top_left_world;
uniform vec2 cam_size_world;
uniform vec2 maze_origin_world;
uniform vec2 maze_size_world;

uniform bool enable_memory = true;

// Explored values decay exponentially and may never hit exactly 0.
// Anything below this cutoff is treated as fully forgotten (pitch black).
// Higher cutoff = snaps to full black sooner.
const float EXPLORED_CUTOFF = 0.001;
// Apply a curve so partial memory darkens noticeably as it decays.
// Higher = fades to black more quickly in the mid-range.
const float EXPLORED_CURVE = 2.0;

void fragment() {
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

	// Snap tiny explored values to 0 so areas can become fully black again.
	exp *= step(EXPLORED_CUTOFF, exp);

	// Unseen = darkness_alpha overlay, explored = explored_alpha overlay.
	// IMPORTANT: exp is treated as a continuous explored amount, so as it decays
	// (fog forgetting) the area smoothly returns toward full darkness.
	float a = darkness_alpha;
	if (cur > 0.0) {
		a = 0.0;
	} else {
		exp = clamp(exp, 0.0, 1.0);
		exp = pow(exp, EXPLORED_CURVE);
		a = mix(darkness_alpha, explored_alpha, exp);
	}

	COLOR = vec4(0.0, 0.0, 0.0, a);
}
