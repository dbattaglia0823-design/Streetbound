shader_type canvas_item;
uniform sampler2D relief : filter_linear, repeat_disable;
varying vec2 world_m;
void vertex() {
	world_m=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy/20.0;
}
void fragment() {
	vec2 uv=world_m/vec2(2800.0,2400.0);
	vec4 field=texture(relief,uv);
	float inside=step(0.0,uv.x)*step(0.0,uv.y)*step(uv.x,1.0)*step(uv.y,1.0);
	float mask=field.a*inside;
	// Leave lakes and river color untouched. Terrain is shaded, not the water.
	float water=step(COLOR.r+0.04,COLOR.b);
	mask*=1.0-water;
	vec3 upland=mix(vec3(.49,.58,.45),vec3(.69,.67,.58),smoothstep(.12,.88,field.g));
	vec3 ground=mix(COLOR.rgb,upland,.45+field.b*.25);
	ground*=.67+field.r*.57;
	COLOR.rgb=mix(COLOR.rgb,ground,mask);
}
