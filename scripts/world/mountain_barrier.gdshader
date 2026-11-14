shader_type canvas_item;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 float stone=smoothstep(.22,.40,COLOR.r);
 float grain=noise(UV*20.0)-.5;
 float layers=sin(UV.y*19.0+noise(UV*.8)*5.0)*.022;
 float fissure=1.0-smoothstep(.015,.08,abs(noise(UV*vec2(2.0,6.0))-.5));
 float detail=1.0-smoothstep(.8,2.5,max(length(dFdx(UV)),length(dFdy(UV))));
 COLOR.rgb+=vec3((grain*.075+layers-fissure*.048)*stone*detail);
}
