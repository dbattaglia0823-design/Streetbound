shader_type canvas_item;
render_mode blend_mix;

// Water is a softly clouded, semi-transparent layer over its baked terrain.
// Two world-space wave scales and a moving turbidity field produce shallow
// coastal swell and smaller ripples without CPU animations or per-frame nodes.
varying vec2 world_metres;

void vertex() {
    world_metres = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / 20.0;
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f*f*(3.0-2.0*f);
    float a = fract(sin(dot(i, vec2(127.1,311.7)))*43758.5453);
    float b = fract(sin(dot(i+vec2(1.0,0.0), vec2(127.1,311.7)))*43758.5453);
    float c = fract(sin(dot(i+vec2(0.0,1.0), vec2(127.1,311.7)))*43758.5453);
    float d = fract(sin(dot(i+vec2(1.0,1.0), vec2(127.1,311.7)))*43758.5453);
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}

void fragment() {
    vec2 p = world_metres;
    float cloud = noise2(p / 59.0 + vec2(TIME * .006, -TIME * .003));
    cloud = cloud*.60 + noise2(p / 17.0 - vec2(TIME*.022,TIME*.009))*.40;
    float swell = sin(p.y*.105+p.x*.045+TIME*.52+cloud*2.1);
    float current = sin(p.x*.32-p.y*.18-TIME*.95);
    float crest = smoothstep(.76,.96,swell)*.45 +
                  smoothstep(.87,.99,current)*.23;
    float muddiness = smoothstep(.22,.82,cloud);
    vec3 nearshore = vec3(.26,.51,.52);
    vec3 silty = vec3(.50,.59,.53);
    vec3 color = mix(nearshore,silty,muddiness*.60);
    color = mix(color,vec3(.70,.80,.73),crest*.55);
    // A real translucent water layer: pale ground and river sediment remain
    // perceptible underneath, while the underlying solid water fill ensures
    // no green land tile shows through at deeper sea.
    COLOR = vec4(color, (.10 + muddiness*.17 + crest*.16) * COLOR.a);
}
