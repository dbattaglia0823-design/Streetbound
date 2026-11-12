shader_type canvas_item;
// Preserve the illustrated scenery atlas's alpha cleanup. Parking lots and
// service aprons painted #464f52 also receive seamless procedural asphalt
// grain in world coordinates, without spawning extra nodes or decals.
varying vec2 world_px;
uniform float parking_asphalt_detail : hint_range(0.0, 1.5) = 1.0;

float hash21(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}
float soft_noise(vec2 p) {
	vec2 f=fract(p);
	f=f*f*(3.0-2.0*f);
	vec2 k=floor(p);
	return mix(mix(hash21(k),hash21(k+vec2(1.0,0.0)),f.x),
		mix(hash21(k+vec2(0.0,1.0)),hash21(k+vec2(1.0,1.0)),f.x),f.y);
}
void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy;
}
void fragment() {
	COLOR.a = smoothstep(0.12,0.90,COLOR.a);
	vec3 asphalt = vec3(70.0,79.0,82.0)/255.0; // #464f52
	vec3 roadway = vec3(88.0,101.0,108.0)/255.0; // #58656c
	float paved = max(1.0 - smoothstep(0.012,0.035,distance(COLOR.rgb,asphalt)),
		1.0 - smoothstep(0.012,0.035,distance(COLOR.rgb,roadway)));
	if (paved > 0.01) {
		float broad = soft_noise(world_px * 0.0033);
		float medium = soft_noise(world_px * 0.027);
		float fade = 1.0-smoothstep(0.42,1.15,length(fwidth(world_px*.36)));
		float stones = (hash21(floor(world_px*.36))-.5) * fade;
		float repaired = smoothstep(.74,.93,broad);
		float aggregate = (broad-.5)*.075+(medium-.5)*.040+stones*.039-repaired*.012;
		COLOR.rgb += vec3(aggregate*.91,aggregate,aggregate*1.07)*paved*parking_asphalt_detail;
	}
}
