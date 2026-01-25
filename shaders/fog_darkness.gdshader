shader_type canvas_item;
uniform sampler2D current_tex : source_color;

void fragment() {
    COLOR = texture(current_tex, UV);
}
