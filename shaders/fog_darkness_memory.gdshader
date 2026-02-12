shader_type canvas_item;

uniform sampler2D current_tex : source_color;    // MaskViewport texture
uniform sampler2D explored_tex : source_color;   // ExploredViewport texture (persistent)

uniform float darkness_alpha = 1.0;              // unexplored darkness
uniform float explored_alpha = 0.60;             // explored-but-not-current darkness
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
        exp = texture(explored_tex, UV).r;
        exp = max(exp, cur); // current implies explored
    }

    // Snap tiny explored values to 0 so areas can become fully black again.
    exp *= step(EXPLORED_CUTOFF, exp);

    // Base alpha: unexplored -> darkness_alpha, explored -> explored_alpha
    exp = clamp(exp, 0.0, 1.0);
    exp = pow(exp, EXPLORED_CURVE);
    float a = mix(darkness_alpha, explored_alpha, exp);

    // Current visibility punches fully through
    a *= (1.0 - cur);

    COLOR = vec4(0.0, 0.0, 0.0, a);
}
