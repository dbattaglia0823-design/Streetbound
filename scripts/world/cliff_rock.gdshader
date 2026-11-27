shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
	// UV.x follows road station; UV.y rises from the foot to the rock lip.
	// Broad broken strata, granular stone and fissures share the same station
	// across chunk boundaries. Very dark vertices are the separate cast shade.
	float is_rock=smoothstep(.24,.38,COLOR.r);
	float broad=noise(UV*vec2(1.2,6.0));
	float strata=sin(UV.y*42.0+noise(UV*vec2(.8,2.0))*5.0)*.025;
	vec2 grain_uv=UV*vec2(37.0,75.0);
	float grain=(noise(grain_uv)-.5)*(1.0-smoothstep(.45,1.4,length(fwidth(grain_uv))));
	vec2 micro_uv=UV*vec2(140.0,180.0);
	float micro=(noise(micro_uv)-.5)*(1.0-smoothstep(.4,1.2,length(fwidth(micro_uv))));
	float strata_fade=1.0-smoothstep(.5,1.5,length(fwidth(UV*42.0)));
	float crack=1.0-smoothstep(.03,.09,abs(noise(UV*vec2(5.0,1.1))-.5));
	COLOR.rgb+=(vec3((broad-.5)*.17+strata*strata_fade+grain*.10+micro*.075-crack*.07))*is_rock;
}
