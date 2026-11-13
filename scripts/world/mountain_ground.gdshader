shader_type canvas_item;
// Stylized world-space ground materials; patterns align across 192m chunks.
uniform sampler2D relief : filter_linear, repeat_disable;
uniform float terrain_detail : hint_range(0.0, 1.5) = 1.0;
varying vec2 world_m;

float hash21(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float field_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float low = mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), blend.x);
	float high = mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), blend.x);
	return mix(low, high, blend.y);
}

// Tiny leaf pairs on a sparse, irregularly jittered world-space grid.
float grass_tuft(vec2 point_m) {
	vec2 grid = point_m * 0.73;
	vec2 index = floor(grid);
	vec2 jitter = vec2(hash21(index + vec2(3.0, 11.0)), hash21(index + vec2(17.0, 5.0))) * 0.54 - 0.27;
	vec2 p = fract(grid) - vec2(0.5) - jitter;
	float left_blade = 1.0 - smoothstep(0.025, 0.075, length(vec2((p.x + 0.085) * 2.8 + p.y * 0.9, p.y * 1.7)));
	float right_blade = 1.0 - smoothstep(0.025, 0.075, length(vec2((p.x - 0.078) * 2.8 - p.y * 0.8, p.y * 1.7)));
	return step(0.48, hash21(index + vec2(29.0, 13.0))) * max(left_blade, right_blade);
}

void vertex() {
	world_m = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / 20.0;
}

void fragment() {
    // Untagged grass blades/flowers retain their original transparent ink.
    // Only polygon UVs >= 2 select a terrain material (no color guessing).
    if (UV.x >= 1.5) {
        int kind = int(round(UV.x));
        vec3 paint = COLOR.rgb;
        float broad = field_noise(world_m * 0.027);
        float medium = field_noise(world_m * 0.16);
        float fine_visibility = 1.0-smoothstep(0.45,1.25,length(fwidth(world_m*4.0)));
        float grit_visibility = 1.0-smoothstep(.4,1.2,length(fwidth(world_m*10.0)));
        float grit = (field_noise(world_m*10.0)-0.5)*grit_visibility;
        vec3 ground = paint;
        bool water = kind==7 || kind==8;
        bool foam = kind==9;
        if (kind==2 || kind==3 || kind==15) {
            float soil_noise = field_noise(world_m * 0.072 + vec2(32.4,13.7));
            float soil_exposure = smoothstep(0.62,0.82,broad*.42+medium*.28+soil_noise*.30);
            vec3 earthy = mix(vec3(.28,.24,.16),vec3(.47,.39,.25),soil_noise);
            ground = mix(vec3(.32,.42,.20),vec3(.46,.55,.29),broad);
            ground *= 0.93+medium*.14+grit*.035;
            float dry = smoothstep(.62,.88,soil_noise);
            ground = mix(ground,vec3(.56,.53,.31),dry*.27);
            if (kind==3) {
                ground = mix(vec3(.19,.27,.17),vec3(.31,.38,.23),broad);
                ground = mix(ground,earthy,medium*.32);
                // Leaf litter is warm and irregular rather than meadow green.
                vec2 leaf_grid = world_m*2.1;
                vec2 leaf_cell = floor(leaf_grid);
                vec2 leaf_center = vec2(hash21(leaf_cell+vec2(7,19)),hash21(leaf_cell+vec2(31,5)))*.7+.15;
                vec2 leaf_point = fract(leaf_grid)-leaf_center;
                vec2 leaf_axis = mix(vec2(2.8,1.0),vec2(1.0,2.8),step(.5,hash21(leaf_cell)));
                float leaves = 1.0-smoothstep(.09,.18,length(leaf_point*leaf_axis));
                ground += vec3(.07,.035,-.004)*leaves*fine_visibility;
            }
            ground = mix(ground,earthy,soil_exposure*.48);
            float blade_visibility = 1.0-smoothstep(.4,1.1,length(fwidth(world_m*.73)));
            float blades = grass_tuft(world_m)*blade_visibility;
            ground *= 1.0-blades*.22;
        } else if (kind==4 || kind==5) {
            float layers = world_m.y*.47+world_m.x*.13+medium*3.4+broad*5.0;
            float strata = smoothstep(.65,.93,sin(layers));
            float fissure = smoothstep(.90,.98,field_noise(world_m*.63));
            ground = mix(vec3(.36,.37,.33),vec3(.57,.55,.47),broad);
            ground *= .94+medium*.16+grit*.10;
            ground -= vec3(.09,.085,.075)*strata*.55;
            ground -= vec3(.11,.10,.085)*fissure;
            ground += vec3(.035,.033,.025)*smoothstep(.35,.60,sin(layers+.14));
        } else if (kind==6 || kind==12) {
            float dune_phase = world_m.y*1.15+world_m.x*.32+medium*1.7;
            float ripple_fade = 1.0-smoothstep(.65,1.6,fwidth(dune_phase));
            ground = mix(vec3(.70,.58,.37),vec3(.87,.77,.55),broad);
            ground += vec3(.028,.023,.014)*sin(dune_phase)*ripple_fade;
            ground += grit*.045;
            if (kind==12) ground *= vec3(1.08,.95,.82);
        } else if (water || foam) {
            float moving = field_noise(world_m*.045+vec2(TIME*.018,-TIME*.012));
            float swell_phase = world_m.y*.46+world_m.x*.16-TIME*.60+medium*2.1;
            float ripple_fade = 1.0-smoothstep(.7,1.8,fwidth(swell_phase));
            float crest = pow(max(0.0,sin(swell_phase)),14.0)*ripple_fade;
            ground = mix(vec3(.12,.31,.39),vec3(.26,.48,.49),moving);
            if (kind==8) ground = mix(vec3(.17,.32,.31),vec3(.29,.45,.39),moving);
            ground += vec3(.07,.10,.10)*crest*(.35+medium*.65);
            if (foam) {
                float broken = smoothstep(.24,.72,medium*.6+moving*.4);
                ground = mix(vec3(.48,.65,.60),vec3(.84,.88,.73),broken);
            }
        } else if (kind==10) {
            float phase = world_m.y*3.5+sin(world_m.x*.035)*.18;
            float rows = (.5+.5*sin(phase))*(1.0-smoothstep(.6,1.7,fwidth(phase)));
            ground = mix(vec3(.40,.35,.22),vec3(.45,.51,.24),broad);
            ground = mix(ground,vec3(.28,.37,.17),rows*.48);
            ground += grit*.03;
        } else if (kind==11) {
            // Concrete/compacted urban ground; roads keep their own material.
            ground = mix(vec3(.47,.47,.41),vec3(.59,.58,.51),broad);
            ground += (medium-.5)*.045+grit*.025;
        } else if (kind==13 || kind==14) {
            ground = kind==13 ? mix(vec3(.35,.25,.16),vec3(.52,.39,.25),broad)
                             : mix(vec3(.39,.39,.35),vec3(.57,.55,.47),broad);
            // Sparse pebble highlights and their darker contact side.
            vec2 cell = world_m*3.2;
            vec2 index = floor(cell);
            vec2 center = vec2(hash21(index+vec2(7,31)),hash21(index+vec2(41,5)))*.62+.19;
            vec2 pebble = fract(cell)-center;
            float radius = mix(.07,.22,hash21(index+vec2(13,29)));
            float occupied = step(.22,hash21(index+vec2(19,71)));
            float stone = 1.0-smoothstep(radius*.55,radius,length(pebble*vec2(1.0,1.35)));
            float shade = 1.0-smoothstep(radius*.5,radius*1.25,length(pebble-vec2(.04,.06)));
            ground += (stone*.12-shade*.085)*fine_visibility*occupied;
            ground += grit*.065;
        }
        // Honor authored color variation modestly, while keeping the material recognizable.
        vec3 reference = vec3(.64,.72,.54);
        if(kind==3) reference=vec3(.44,.55,.44);
        else if(kind==4 || kind==5 || kind==15) reference=vec3(.61,.67,.63);
        else if(kind==6 || kind==12) reference=vec3(.89,.83,.67);
        else if(water) reference=vec3(.51,.71,.71);
        else if(foam) reference=vec3(.78,.85,.79);
        else if(kind==10) reference=vec3(.71,.74,.54);
        else if(kind==11) reference=vec3(.69,.71,.63);
        vec3 tint = clamp(paint/max(reference,vec3(.1)),vec3(.75),vec3(1.25));
        ground *= mix(vec3(1.0),tint,.25);
        // Preserve relief lighting without painting every upland region the same green.
        vec2 uv = world_m/vec2(2800.0,2400.0);
        vec4 field = texture(relief,uv);
        float inside = step(0.0,uv.x)*step(0.0,uv.y)*step(uv.x,1.0)*step(uv.y,1.0);
        float relief_mask = field.a*inside*(water || foam ? 0.0 : 1.0);
        ground *= mix(1.0,.73+field.r*.45,relief_mask);
        COLOR.rgb = clamp(mix(paint,ground,clamp(terrain_detail,0.0,1.0)),vec3(0.0),vec3(1.0));
    }
}
