shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float curvature : hint_range(0.0, 0.25) = 0.09;   // screen bulge
uniform float vignette  : hint_range(0.0, 1.0)  = 0.35;   // edge darkening
uniform float scanlines : hint_range(0.0, 1.0)  = 0.25;   // scanline strength
uniform float aberration_px : hint_range(0.0, 3.0) = 1.0; // chroma offset in pixels
uniform float noise     : hint_range(0.0, 1.0)  = 0.06;   // subtle film noise
uniform float glow      : hint_range(0.0, 1.0)  = 0.12;   // soft bloom-ish

vec2 curve_uv(vec2 uv, float amount)
{
	// map 0..1 to -1..1
	vec2 p = uv * 2.0 - 1.0;

	// barrel distortion
	vec2 p2 = p * p;
	p += p * (p2.yx) * amount;

	// back to 0..1
	return p * 0.5 + 0.5;
}

float rand(vec2 co)
{
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment()
{
	vec2 tex_size = vec2(textureSize(screen_tex, 0));
	vec2 px = 1.0 / tex_size;

	// Curved CRT
	vec2 uv = curve_uv(UV, curvature);

	// Outside the curved screen -> black
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec3 center = texture(screen_tex, uv).rgb;
		float lum0 = max(max(center.r, center.g), center.b);
		// For near-black pixels, disable effects that can bleed brightness from neighbors.
		float fx_gate = smoothstep(0.03, 0.12, lum0);

		// Chromatic aberration (tiny RGB split, in pixels)
		float off = aberration_px * fx_gate;
		vec3 col;
		col.r = texture(screen_tex, uv + vec2(off, 0.0) * px).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - vec2(off, 0.0) * px).b;

		// Cheap "glow": mix with a slightly blurred sample
		vec3 blur = (
			texture(screen_tex, uv + vec2( 1.0, 0.0) * px).rgb +
			texture(screen_tex, uv + vec2(-1.0, 0.0) * px).rgb +
			texture(screen_tex, uv + vec2( 0.0, 1.0) * px).rgb +
			texture(screen_tex, uv + vec2( 0.0,-1.0) * px).rgb
		) * 0.25;

		col = mix(col, blur, glow * fx_gate);

		// Scanlines (tied to screen pixels)
		float line = sin((uv.y * tex_size.y) * 3.14159265);
		float scan = mix(1.0, 0.85 + 0.15 * line, scanlines);
		col *= scan;

		// Vignette (soft edge darkening)
		vec2 d = uv - 0.5;
		float vig = 1.0 - vignette * smoothstep(0.15, 0.85, dot(d, d) * 1.8);
		col *= vig;

		// Subtle noise
		float n = rand(uv * tex_size + TIME * 60.0) - 0.5;
		// Don't lift pitch black: gate noise by the center brightness.
		col += n * noise * fx_gate;
		col = max(col, vec3(0.0));

		COLOR = vec4(col, 1.0);
	}
}
