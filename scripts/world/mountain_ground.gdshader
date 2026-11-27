shader_type canvas_item;
uniform bool terrain_cut_enabled = false;
uniform sampler2D terrain_cut_mask : filter_nearest, repeat_disable;
uniform vec4 terrain_cut_rect = vec4(0.0,0.0,1.0,1.0);

// High-detail world-space ground materials; patterns align across 192m chunks.
uniform sampler2D relief : filter_linear, repeat_disable;
uniform float terrain_detail : hint_range(0.0, 1.5) = 1.0;
// Visual-only relief, independent of driving physics and authoring geometry.
uniform float terrain_shadow_strength : hint_range(0.0, 1.0) = 1.0;
const vec2 SUN_DIRECTION = vec2(-0.65,-0.76);
const vec2 RELIEF_EXTENT = vec2(2800.0,2400.0);
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

// Analytic derivatives of the smooth world-space height noise. The same
// hill normal is obtained regardless of zoom, frame or chunk partition.
vec2 hill_gradient(vec2 p) {
    vec2 cell=floor(p);
    vec2 f=fract(p);
    vec2 t=f*f*(3.0-2.0*f);
    vec2 dt=6.0*f*(1.0-f);
    float a=hash21(cell);
    float b=hash21(cell+vec2(1.0,0.0));
    float c=hash21(cell+vec2(0.0,1.0));
    float d=hash21(cell+vec2(1.0,1.0));
    return vec2(mix(b-a,d-c,t.y)*dt.x,mix(c-a,d-b,t.x)*dt.y);
}

// Fixed, bounded horizon samples toward the northwest sunlight. The existing
// relief map stores height / 1200 in green and coverage in alpha.
float horizon_occlusion(vec2 uv,float height_m,float distance_m) {
    vec2 at=uv+SUN_DIRECTION*distance_m/RELIEF_EXTENT;
    vec4 sample_height=texture(relief,at);
    float valid=step(0.0,at.x)*step(0.0,at.y)*step(at.x,1.0)*step(at.y,1.0);
    float above=sample_height.g*1200.0-height_m-distance_m*.62;
    // Feather the quantized height field to avoid staircase shadow edges.
    return smoothstep(-5.0,10.0+distance_m*.075,above)*sample_height.a*valid;
}

float local_hill_light(vec2 at,float amplitude) {
    // Two distinct scales: broad rolling hills and smaller folds/valleys.
    vec2 gradient=hill_gradient(at*.012+vec2(19.0,7.0))*.88;
    gradient+=hill_gradient(at*.038+vec2(5.0,38.0))*.49;
    vec3 normal=normalize(vec3(-gradient*amplitude,1.0));
    vec3 sunlight=normalize(vec3(SUN_DIRECTION,.75));
    float diffuse=dot(normal,sunlight);
    float level_light = sunlight.z;
    return clamp(1.0+(diffuse-level_light)*.69,.59,1.25);
}

// Filter high spatial frequencies before sampling their contribution.
float detail_fade(vec2 coord) {
    return 1.0-smoothstep(.38,1.15,length(fwidth(coord)));
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
	if (terrain_cut_enabled) {
		vec2 cut_uv = (world_m-terrain_cut_rect.xy)/terrain_cut_rect.zw;
		if (all(greaterThanEqual(cut_uv,vec2(0.0))) && all(lessThan(cut_uv,vec2(1.0))) && texture(terrain_cut_mask,cut_uv).r > .5) { discard; }
	}

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
        // A finer, sub-decimetre material layer remains sharp at driving zoom.
        vec2 micro_coord = world_m*22.0;
        float micro = (field_noise(micro_coord)-.5)*detail_fade(micro_coord);
        vec2 detail_coord = world_m*2.6;
        float detail = field_noise(detail_coord+vec2(18.1,7.3));
        float detail_visible = detail_fade(detail_coord);
        float relief_grain = (detail-.5)*detail_visible;
        vec3 ground = paint;
        bool water = kind==7 || kind==8;
        bool foam = kind==9;
        if (kind==2 || kind==3 || kind==15) {
            float soil_noise = field_noise(world_m * 0.072 + vec2(32.4,13.7));
            float soil_exposure = smoothstep(0.62,0.82,broad*.42+medium*.28+soil_noise*.30);
            vec3 earthy = mix(vec3(.28,.24,.16),vec3(.47,.39,.25),soil_noise);
            ground = mix(vec3(.32,.42,.20),vec3(.46,.55,.29),broad);
            ground *= 0.88+medium*.22+grit*.10+micro*.065;
            ground += vec3(.045,.065,.018)*relief_grain;
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
                ground += vec3(.105,.052,.005)*leaves*fine_visibility;
                ground += vec3(.040,.026,.012)*relief_grain;
            }
            ground = mix(ground,earthy,soil_exposure*.60);
            // Small organic clumps and soil gaps rather than uniform noise.
            float clump = smoothstep(.58,.82,detail)*detail_visible;
            ground *= 1.0-clump*.13;
            ground += vec3(.045,.055,.012)*smoothstep(.68,.93,detail)*detail_visible;
            float blade_visibility = 1.0-smoothstep(.4,1.1,length(fwidth(world_m*.73)));
            float blades = grass_tuft(world_m)*blade_visibility;
            ground *= 1.0-blades*.22;
        } else if (kind==4 || kind==5) {
            float layers = world_m.y*.47+world_m.x*.13+medium*3.4+broad*5.0;
            float ridge = 1.0-abs(2.0*detail-1.0);
            float fracture = (1.0-smoothstep(.025,.095,abs(detail-.5)))*detail_visible;
            float strata = smoothstep(.65,.93,sin(layers));
            float fissure = smoothstep(.90,.98,field_noise(world_m*.63));
            ground = mix(vec3(.36,.37,.33),vec3(.57,.55,.47),broad);
            ground *= .87+medium*.23+grit*.18+micro*.12;
            ground += vec3(.07,.065,.052)*(ridge-.5)*detail_visible;
            ground -= vec3(.075,.067,.055)*fracture;
            ground -= vec3(.09,.085,.075)*strata*.55;
            ground -= vec3(.11,.10,.085)*fissure;
            ground += vec3(.035,.033,.025)*smoothstep(.35,.60,sin(layers+.14));
        } else if (kind==6 || kind==12) {
            float dune_phase = world_m.y*1.15+world_m.x*.32+medium*1.7;
            float ripple_fade = 1.0-smoothstep(.65,1.6,fwidth(dune_phase));
            ground = mix(vec3(.70,.58,.37),vec3(.87,.77,.55),broad);
            ground += vec3(.028,.023,.014)*sin(dune_phase)*ripple_fade;
            ground += grit*.09+micro*.055;
            ground += vec3(.05,.037,.022)*relief_grain;
            float sand_ridge = pow(max(0.0,sin(dune_phase*2.7+detail*.55)),4.0);
            ground += vec3(.025,.019,.012)*sand_ridge*detail_fade(world_m*2.7);
            if (kind==12) ground *= vec3(1.08,.95,.82);
        } else if (water || foam) {
            float moving = field_noise(world_m*.045+vec2(TIME*.018,-TIME*.012));
            float swell_phase = world_m.y*.46+world_m.x*.16-TIME*.60+medium*2.1;
            float ripple_fade = 1.0-smoothstep(.7,1.8,fwidth(swell_phase));
            float crest = pow(max(0.0,sin(swell_phase)),14.0)*ripple_fade;
            ground = mix(vec3(.12,.31,.39),vec3(.26,.48,.49),moving);
            if (kind==8) ground = mix(vec3(.17,.32,.31),vec3(.29,.45,.39),moving);
            ground += vec3(.07,.10,.10)*crest*(.35+medium*.65);
            float short_wave = world_m.x*1.63-world_m.y*.83+TIME*.95+medium*2.0;
            float chop = pow(max(0.0,sin(short_wave)),9.0)*(1.0-smoothstep(.6,1.6,fwidth(short_wave)));
            ground += vec3(.045,.067,.072)*chop*(.30+detail*.70);
            ground += vec3(.018,.028,.032)*relief_grain;
            if (foam) {
                float broken = smoothstep(.24,.72,medium*.6+moving*.4);
                ground = mix(vec3(.48,.65,.60),vec3(.84,.88,.73),broken);
            }
        } else if (kind==10) {
            float phase = world_m.y*3.5+sin(world_m.x*.035)*.18;
            float rows = (.5+.5*sin(phase))*(1.0-smoothstep(.6,1.7,fwidth(phase)));
            ground = mix(vec3(.40,.35,.22),vec3(.45,.51,.24),broad);
            ground = mix(ground,vec3(.28,.37,.17),rows*.48);
            ground += grit*.07+micro*.035;
            ground += vec3(.045,.06,.025)*relief_grain*rows;
        } else if (kind==11) {
            // Concrete/compacted urban ground; roads keep their own material.
            ground = mix(vec3(.47,.47,.41),vec3(.59,.58,.51),broad);
            ground += (medium-.5)*.065+grit*.10+micro*.05+relief_grain*.04;
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
            ground += grit*.12+micro*.08+relief_grain*.06;
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
        vec2 uv = world_m/RELIEF_EXTENT;
        vec4 field = texture(relief,uv);
        float inside = step(0.0,uv.x)*step(0.0,uv.y)*step(uv.x,1.0)*step(uv.y,1.0);
        float relief_mask = field.a*inside*(water || foam ? 0.0 : 1.0);
        // Preserve the original large-scale relief texture, then add bounded
        // procedural ridge detail at 2–30 m without altering actual height.
        float upland = relief_mask*smoothstep(.10,.42,field.g);
        float slope = clamp(field.b,0.0,1.0);
        float ridge_field = field_noise(world_m*vec2(.115,.085)+vec2(27.1,4.3));
        float erosion = 1.0-abs(2.0*ridge_field-1.0);
        float ridge_shade = (erosion-.5)*.16 + relief_grain*.055;
        float exposed = upland*smoothstep(.22,.78,slope*.72+ridge_field*.28);
        if (kind==4 || kind==5 || kind==15) {
            vec3 exposed_rock = mix(vec3(.34,.36,.32),vec3(.55,.53,.46),medium);
            ground = mix(ground,exposed_rock,exposed*.38);
        }
        ground *= mix(1.0,.65+field.r*.63+ridge_shade,relief_mask);
        if (!water && !foam && terrain_shadow_strength>0.0) {
            // Urban paving is mostly flat; fields and beaches remain subtle.
            float amplitude=.70;
            if(kind==4 || kind==5 || kind==15) amplitude=1.45;
            else if(kind==3) amplitude=.96;
            else if(kind==6 || kind==10) amplitude=.24;
            else if(kind==12) amplitude=.58;
            else if(kind==11) amplitude=.10;
            float local_light=local_hill_light(world_m,amplitude);
            // Keep regional mountain shadows grounded in the baked elevation.
            // Custom maps use a transparent relief texture: local hills still work.
            float regional_shadow=0.0;
            if (relief_mask>.005) {
                float height_m=field.g*1200.0;
                regional_shadow=max(horizon_occlusion(uv,height_m,36.0),
                    max(horizon_occlusion(uv,height_m,100.0),horizon_occlusion(uv,height_m,240.0)))*relief_mask;
            }
            float light_factor=mix(1.0,local_light*(1.0-regional_shadow*.29),terrain_shadow_strength);
            // Slightly cool the shaded slopes and warm the sunlit ridges.
            vec3 directional_tint=mix(vec3(1.0),vec3(.94,.97,1.02),clamp((1.0-light_factor)*1.8,0.0,1.0));
            directional_tint=mix(directional_tint,vec3(1.025,1.012,.98),clamp((light_factor-1.0)*2.0,0.0,1.0));
            ground*=light_factor*directional_tint;
        }
        COLOR.rgb = clamp(mix(paint,ground,clamp(terrain_detail,0.0,1.0)),vec3(0.0),vec3(1.0));
    }
}
