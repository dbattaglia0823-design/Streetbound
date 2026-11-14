shader_type canvas_item;
varying vec2 world_m;
void vertex(){world_m=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy/20.0;}
void fragment(){
 vec3 base=COLOR.rgb;
 float swell=sin(world_m.x*.09+world_m.y*.14-TIME*.45);
 float ripple=sin(world_m.x*.73-world_m.y*.36+TIME*.9+swell*1.3);
 float fade=1.0-smoothstep(.6,2.0,length(fwidth(world_m)));
 float glint=pow(max(0.0,ripple),18.0)*fade;
 COLOR=vec4(base*(.97+.035*swell)+vec3(.12,.16,.15)*glint*.4,COLOR.a);
}
