shader_type canvas_item;
// Stylized world-space ground materials; patterns align across 192m chunks.
uniform sampler2D relief : filter_linear, repeat_disable;
uniform float terrain_detail : hint_range(0.0, 1.5) = 1.0;
varying vec2 world_m;

float hash21(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float field_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float low = mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), blend.x);
	float high = mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), blend.x);
	return mix(low, high, blend.y);
}

// Tiny leaf pairs on a sparse, irregularly jittered world-space grid.
float grass_tuft(vec2 point_m) {
	vec2 grid = point_m * 0.73;
	vec2 index = floor(grid);
	vec2 jitter = vec2(hash21(index + vec2(3.0, 11.0)), hash21(index + vec2(17.0, 5.0))) * 0.54 - 0.27;
	vec2 p = fract(grid) - vec2(0.5) - jitter;
	float left_blade = 1.0 - smoothstep(0.025, 0.075, length(vec2((p.x + 0.085) * 2.8 + p.y * 0.9, p.y * 1.7)));
	float right_blade = 1.0 - smoothstep(0.025, 0.075, length(vec2((p.x - 0.078) * 2.8 - p.y * 0.8, p.y * 1.7)));
	return step(0.48, hash21(index + vec2(29.0, 13.0))) * max(left_blade, right_blade);
}

void vertex() {
	world_m = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / 20.0;
}

void fragment() {
	vec3 paint = COLOR.rgb;
	// Palettes from Morrow Coast polygons; road surfaces use another shader.
	float water = step(0.14, paint.b - paint.r) * step(0.64, paint.b);
	float sand = step(0.82, paint.r) * (1.0 - step(0.74, paint.b));
	float foam = step(0.75, paint.r) * step(0.82, paint.g) * step(0.78, paint.b);
	float broad = field_noise(world_m * 0.027);
	float medium = field_noise(world_m * 0.16);
	float grit = hash21(floor(world_m * 3.1));
	float vegetation = clamp((paint.g - paint.b - 0.008) * 5.0, 0.0, 1.0);
	float patch = (broad - 0.5) * mix(0.07, 0.20, vegetation);
	float small = (medium - 0.5) * 0.09 + (grit - 0.5) * 0.025;
	vec3 meadow = paint * (1.0 + (patch + small) * terrain_detail);
	// Natural grass and warm bare-soil breaks, tied to WORLD metres rather
	// than the current 192m chunk. These patches do not affect traction.
	float soil_noise = field_noise(world_m * 0.072 + vec2(32.4, 13.7));
	float soil_exposure = smoothstep(.57,.79,
		broad*.47 + medium*.27 + soil_noise*.26);
	meadow = mix(meadow,meadow*vec3(.85,1.055,.81),
		clamp(vegetation*.70*terrain_detail,0.0,0.85));
	vec3 earthy = mix(vec3(.39,.35,.27),vec3(.59,.50,.35),soil_noise);
	meadow = mix(meadow,earthy,soil_exposure*.57*vegetation*terrain_detail);
	float dry = smoothstep(0.57, 0.87, broad * 0.85 + medium * 0.15);
	meadow = mix(meadow, meadow * vec3(1.075, 1.045, 0.91), dry * 0.29 * vegetation * terrain_detail);
	// Grass silhouettes progressively fade below a screen pixel instead of
	// aliasing into a crawling high-frequency pattern at far camera zoom.
	float blade_visibility = 1.0 - smoothstep(0.45, 1.05, length(fwidth(world_m * 0.73)));
	float blade = grass_tuft(world_m) * blade_visibility * vegetation * terrain_detail;
	meadow = mix(meadow, meadow * vec3(0.57, 0.77, 0.53), clamp(blade * 0.31, 0.0, 1.0));

	// Soft beach granules, and restrained static water ripples.
	vec3 beach = paint * (1.0 + ((broad - 0.5) * 0.12 + (medium - 0.5) * 0.10 + (grit - 0.5) * 0.07) * terrain_detail);
	beach += vec3(0.020, 0.015, 0.009) * smoothstep(0.92, 1.0, grit) * terrain_detail;
	// Drier higher sand flecks and darker packed patches reuse existing noise,
	// producing natural shallow depth without another sampled texture.
	beach *= 1.0 - smoothstep(0.73, 0.96, medium) * 0.045 * terrain_detail;
	// Wind-driven water is evaluated in world metres, not per streamed cell:
	// all ocean, river and lake polygons therefore share seamless motion.
	// Two low-frequency noise layers give the muted, silt-clouded look of
	// natural coastal water without texture allocations or CPU animation.
	vec2 drift = vec2(TIME * 0.045, -TIME * 0.025);
	float turbidity = field_noise(world_m * 0.046 + drift);
	float sediment = field_noise(world_m * 0.12 - drift * 1.65);
	float cloud = smoothstep(0.24, 0.82, turbidity * 0.70 + sediment * 0.30);
	vec3 deep_water = paint * vec3(0.69, 0.84, 0.88);
	vec3 shallow_water = paint * vec3(1.13, 1.09, 0.92);
	vec3 lagoon = mix(deep_water, shallow_water, cloud * 0.70 + 0.12);
	// Broad slow-moving swells carry thinner, faster capillary ripples.
	// Derivative filtering removes tiny waves when zoomed far out.
	float swell = sin(world_m.y * 0.30 + world_m.x * 0.12
		- TIME * 0.75 + (turbidity - 0.5) * 2.6);
	float cross_swell = sin(world_m.x * 0.22 - world_m.y * 0.15
		+ TIME * 0.49 + sediment * 1.4);
	float ripple_phase = world_m.y * 2.15 + world_m.x * 0.34
		- TIME * 1.85 + sin(world_m.x * 0.29 + TIME * 0.27);
	float ripple_visibility = 1.0 - smoothstep(0.8, 2.2, fwidth(ripple_phase));
	float ripple = smoothstep(0.74, 0.985, sin(ripple_phase))
		* ripple_visibility;
	float wave_light = swell * 0.033 + cross_swell * 0.018;
	lagoon = clamp(lagoon + vec3(wave_light * 0.78, wave_light, wave_light * 1.08)
		+ vec3(0.021, 0.032, 0.028) * ripple * terrain_detail,
		vec3(0.0), vec3(1.0));

	vec3 textured = mix(meadow, beach, sand);
	textured = mix(textured, lagoon, water);
	// Narrow breaker/riverbank foam drifts subtly rather than remaining ink-flat.
	vec3 foam_tint = paint * (0.95 + 0.05 * sin(world_m.y * 0.55 + world_m.x * 0.19 - TIME * 0.7));
	textured = mix(textured, foam_tint, foam);

	// Preserve the existing northwest-lit terrain relief, never tinting water.
	vec2 uv = world_m / vec2(2800.0, 2400.0);
	vec4 field = texture(relief, uv);
	float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
	float relief_mask = field.a * inside * (1.0 - water) * (1.0 - foam);
	vec3 upland = mix(vec3(0.49, 0.58, 0.45), vec3(0.69, 0.67, 0.58), smoothstep(0.12, 0.88, field.g));
	vec3 shaded = mix(textured, upland, 0.45 + field.b * 0.25);
	shaded *= 0.67 + field.r * 0.57;
	COLOR.rgb = clamp(mix(textured, shaded, relief_mask), vec3(0.0), vec3(1.0));
	// Let the ground/base layer show faintly through the silty water; higher
	// turbidity makes it less transparent. Keep land and foam fully opaque.
	COLOR.a *= mix(1.0, mix(0.84, 0.94, cloud), water);
}
