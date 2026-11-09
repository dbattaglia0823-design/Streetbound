shader_type canvas_item;
// Remove the atlas's very faint translucent matte, preserving soft art edges.
void fragment() {
	COLOR.a = smoothstep(0.12, 0.90, COLOR.a);
}
