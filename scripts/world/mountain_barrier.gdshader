shader_type canvas_item;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 float stone=smoothstep(.22,.40,COLOR.r);
 float grain=noise(UV*32.0)-.5;
 float fine=(noise(UV*120.0)-.5)*(1.0-smoothstep(.4,1.2,length(fwidth(UV*120.0))));
 float facets=noise(UV*vec2(7.0,11.0));
 float layers=sin(UV.y*19.0+noise(UV*.8)*5.0)*.022;
 float fissure=1.0-smoothstep(.015,.08,abs(noise(UV*vec2(2.0,6.0))-.5));
 float detail=1.0-smoothstep(.45,1.5,length(fwidth(UV*32.0)));
 float layer_fade=1.0-smoothstep(.5,1.6,length(fwidth(UV*19.0)));
 COLOR.rgb+=vec3((grain*.10*detail+fine*.095+layers*layer_fade-fissure*.065*layer_fade+(facets-.5)*.075)*stone);
}
