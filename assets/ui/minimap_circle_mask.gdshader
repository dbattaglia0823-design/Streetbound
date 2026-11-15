shader_type canvas_item;

// Applied to the completed map texture, AFTER all native map chunks,
// labels, markers and cursor have rendered in the isolated SubViewport.
// Clipping the final image ensures no high-z child can escape the circle.
uniform bool circle_mode = false;

void fragment() {
	vec4 map_color = texture(TEXTURE, UV);
	if (circle_mode) {
		float radius = length((UV - vec2(0.5)) * 2.0);
		float feather = max(fwidth(radius), 0.005);
		float inside = 1.0 - smoothstep(0.974 - feather, 0.974 + feather, radius);
		float border = smoothstep(0.937, 0.951, radius)
			* (1.0 - smoothstep(0.964, 0.976, radius));
		map_color.rgb = mix(map_color.rgb, vec3(0.851, 0.902, 0.776), border * 0.94);
		map_color.a *= inside;
	}
	COLOR = map_color;
}
