shader_type canvas_item;
render_mode blend_sub, unshaded;

// Amount to subtract from the explored mask this frame.
// With a value of 0.3 per second, explored reaches 0 in ~3.3 seconds.
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	COLOR = vec4(amount, amount, amount, 1.0);
}
