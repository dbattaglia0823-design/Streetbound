shader_type canvas_item;
render_mode unshaded, blend_mix;

// Animated water optics use shared WORLD coordinates so streamed 192m chunks
// never form rectangular texture seams. Underlying seabed color remains visible.
uniform vec2 chunk_origin_px = vec2(0.0);
uniform float pixels_per_metre = 20.0;
varying vec2 world_m;
void vertex() {
    world_m = (VERTEX + chunk_origin_px) / pixels_per_metre;
}
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0,0.0)), f.x),
               mix(hash21(i + vec2(0.0,1.0)), hash21(i + vec2(1.0,1.0)), f.x), f.y);
}
void fragment() {
    vec2 p = world_m;
    float t = TIME * 0.16;
    float broad = smooth_noise(p * 0.014 + vec2(t * .16, -t * .11));
    float cloud = smooth_noise(p * 0.056 + vec2(-t * .23, t * .17));
    float depth = mix(broad, cloud, .38);
    float ripples = sin(p.x * .38 + sin(p.y * .21 + t * 4.0) * 1.9
                  + t * 7.0);
    float crossing = sin((p.x + p.y * .63) * .23 - t * 5.5);
    float flecks = smoothstep(.76, .96, .5 + .25 * ripples + .22 * crossing);
    vec3 deep = vec3(.09,.24,.28);
    vec3 shallow = vec3(.48,.70,.66);
    vec3 tint = mix(deep, shallow, clamp(depth * .8 + .16, .0, 1.0));
    tint += vec3(.21,.28,.22) * flecks * .23;
    // This is a genuinely alpha-blended water layer over the seabed fill.
    COLOR = vec4(tint, clamp(.26 + depth * .31 + flecks * .09,.19,.68));
}