shader_type canvas_item;

uniform sampler2D current_tex : source_color;    // MaskViewport texture
uniform sampler2D explored_tex : source_color;   // ExploredViewport texture (persistent)

uniform float darkness_alpha = 1.0;              // unexplored darkness
uniform float explored_alpha = 0.60;             // explored-but-not-current darkness
uniform bool enable_memory = true;

void fragment() {
    float cur = texture(current_tex, UV).r;

    float exp = 0.0;
    if (enable_memory) {
        exp = texture(explored_tex, UV).r;
        exp = max(exp, cur); // current implies explored
    }

    // Base alpha: unexplored -> darkness_alpha, explored -> explored_alpha
    float a = mix(darkness_alpha, explored_alpha, exp);

    // Current visibility punches fully through
    a *= (1.0 - cur);

    COLOR = vec4(0.0, 0.0, 0.0, a);
}
