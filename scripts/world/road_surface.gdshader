shader_type canvas_item;
varying vec2 world_pixel;
// No additional road decals or textures: all wear is chunk-seam-free.
uniform float road_detail : hint_range(0.0, 1.5) = 1.0;
float hash21(vec2 p) {
	vec3 h=fract(vec3(p.xyx)*0.1031);
	h+=dot(h,h.yzx+33.33);
	return fract((h.x+h.y)*h.z);
}
float grain(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
	world_pixel=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy;
}
void fragment() {
	vec3 asphalt=vec3(0.345098,0.396078,0.423529);
	float paved=1.0-smoothstep(0.008,0.026,distance(COLOR.rgb,asphalt));
	float gravel=1.0-smoothstep(0.008,0.026,distance(COLOR.rgb,vec3(0.63137,0.58039,0.49020)));
	// Reuse the original three noise samples; no extra texture reads or
	// surface nodes are required. Mip-scale fade avoids shimmer on zoom-out.
	float fine=grain(world_pixel*.29);
	float broad=grain(world_pixel*.008);
	float loose=grain(world_pixel*.14);
	float anti_alias=1.0-smoothstep(.55,1.5,length(fwidth(world_pixel*.29)));
	float aggregate=(fine-.5)*.020*anti_alias+(broad-.5)*.024;
	float weathering=smoothstep(.69,.91,broad)*.028;
	// Rare soft resurfacing scars break up broad flat asphalt without hard
	// grid seams; each patch is deterministic in global world coordinates.
	vec2 patch_grid=world_pixel/360.0;
	vec2 patch_cell=floor(patch_grid);
	vec2 patch_local=fract(patch_grid)-vec2(.5);
	float spot=1.0-smoothstep(.24,.42,length(patch_local*vec2(1.0,1.25)));
	float sealed=step(.963,hash21(patch_cell+vec2(61.0,23.0)))*spot;
	float asphalt_variation=(aggregate-weathering-sealed*.033)*paved;
	float gravel_variation=(loose-.5)*.048+(broad-.5)*.018;
	COLOR.rgb+=(asphalt_variation+gravel_variation*gravel)*road_detail;
}
