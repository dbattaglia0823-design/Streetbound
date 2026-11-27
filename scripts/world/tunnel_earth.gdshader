shader_type canvas_item;
varying vec2 world_m;
float hash21(vec2 p){
	vec3 h=fract(vec3(p.xyx)*.1031);
	h+=dot(h,h.yzx+33.33);
	return fract((h.x+h.y)*h.z);
}
float grain(vec2 p){
	vec2 i=floor(p),f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void vertex(){world_m=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy/20.0;}
void fragment(){
	vec2 p=world_m*5.0;
	float filtered=1.0-smoothstep(.4,1.2,length(fwidth(p)));
	float texture_detail=(grain(p)-.5)*.10*filtered+(grain(world_m*.53)-.5)*.085;
	float layers=sin(world_m.y*2.2+world_m.x*.8+grain(world_m*.8)*3.0);
	COLOR.rgb=clamp(COLOR.rgb*(1.0+texture_detail+layers*.025*filtered),vec3(0.0),vec3(1.0));
}
