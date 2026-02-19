shader_type canvas_item;
render_mode unshaded;

uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float pixel_size = 6.0;
uniform float edge : hint_range(0.0, 0.3) = 0.08;
uniform float noise_scale = 80.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.25;
uniform float flicker_speed = 18.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV) * COLOR;

	vec2 texel = max(TEXTURE_PIXEL_SIZE, vec2(0.000001));
	vec2 grid = vec2(pixel_size) * texel;
	vec2 cell = floor(UV / grid) * grid;

	float n = hash(cell * noise_scale);

	// Flicker only while forming (goes to 0 as reveal->1)
	float early = 1.0 - reveal;
	float f = (sin(TIME * flicker_speed + n * 6.2831) * 0.5 + 0.5) * flicker * early;

	float r = clamp(reveal + f, 0.0, 1.0);

	// Inverted threshold so reveal=0 hides, reveal=1 shows
	float m = smoothstep(1.0 - r - edge, 1.0 - r + edge, n);

	// Hard guarantee: fully revealed means fully visible
	if (reveal >= 0.999) {
		m = 1.0;
	}

	vec3 noise_col = vec3(n);
	vec3 rgb = mix(noise_col, src.rgb, m);
	float a = src.a * m;

	COLOR = vec4(rgb, a);
}
