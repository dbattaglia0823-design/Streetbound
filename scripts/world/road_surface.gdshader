shader_type canvas_item;
varying vec2 world_pixel;
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
	float aggregate=(grain(world_pixel*.29)-.5)*.018+(grain(world_pixel*.008)-.5)*.012;
	COLOR.rgb+=aggregate*paved+(grain(world_pixel*.14)-.5)*.045*gravel;
}
