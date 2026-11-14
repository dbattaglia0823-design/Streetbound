shader_type canvas_item;
uniform sampler2D shore_distance : filter_linear,repeat_disable;
uniform vec4 shore_bounds;
uniform float distance_scale=1.0;
uniform bool ocean=false;
varying vec2 world_m;
void vertex(){world_m=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy/20.0;}
void fragment(){
 vec2 uv=(world_m-shore_bounds.xy)/shore_bounds.zw;
 float shore=texture(shore_distance,uv).r*distance_scale;
 float depth=1.0-exp(-shore/(ocean?85.0:55.0));
 vec3 base=mix(vec3(.40,.61,.58),ocean?vec3(.10,.27,.39):vec3(.13,.33,.34),depth);
 float swell=sin(world_m.x*.09+world_m.y*.14-TIME*.45);
 float ripple=sin(world_m.x*.73-world_m.y*.36+TIME*.9+swell*1.3);
 float fade=1.0-smoothstep(.6,2.0,length(fwidth(world_m)));
 float glint=pow(max(0.0,ripple),18.0)*fade;
 float lap=pow(max(0.0,sin(shore*1.3-TIME*.8+swell*.3)),10.0)*exp(-shore/4.0)*fade;
 COLOR=vec4(base*(.98+.02*swell)+vec3(.10,.14,.14)*glint*.28+vec3(.20,.24,.20)*lap*.28,1.0);
}
