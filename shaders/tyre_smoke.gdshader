shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────
// TYRE SMOKE - Stylized with depth & broken edges
// ─────────────────────────────────────────────

uniform vec4 smoke_color_light : source_color = vec4(0.65, 0.63, 0.6, 0.6);
uniform vec4 smoke_color_dark : source_color = vec4(0.35, 0.33, 0.3, 0.7);
uniform float alpha_multiplier : hint_range(0.0, 3.0) = 1.8;
uniform float noise_scale : hint_range(1.0, 8.0) = 3.0;
uniform float edge_breakup : hint_range(0.0, 1.0) = 0.7;
uniform float tendril_strength : hint_range(0.0, 1.0) = 0.5;

varying vec2 v_uv;
varying float v_seed;
varying float v_depth_layer;  // 0 = back (dark), 1 = front (light)

// ─────────────────────────────────────────────
// NOISE
// ─────────────────────────────────────────────

float hash(float n) { return fract(sin(n) * 43758.5453123); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.2;
        amplitude *= 0.45;
    }
    return value;
}

// Wispy tendril noise - creates stretched, smoke-like patterns
float tendril_noise(vec2 p, float seed) {
    // Stretch in a random direction per particle
    float angle = seed * 6.28;
    mat2 rot = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
    vec2 stretched = rot * p;
    stretched.x *= 2.5;  // Stretch horizontally
    stretched = rot * stretched;  // Rotate back

    return fbm(stretched * 1.5, 3);
}

// ─────────────────────────────────────────────
// VERTEX
// ─────────────────────────────────────────────

void vertex() {
    v_uv = UV;

    // Per-particle random values
    float id = float(INSTANCE_ID);
    v_seed = hash(id * 12.9898);

    // Depth layer - some particles are "behind" (darker) others "in front" (lighter)
    v_depth_layer = hash(id * 45.123);

    // Billboard
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0],
        INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2],
        MODEL_MATRIX[3]
    );
}

// ─────────────────────────────────────────────
// FRAGMENT
// ─────────────────────────────────────────────

void fragment() {
    vec2 centered = v_uv * 2.0 - 1.0;
    float dist = length(centered);

    // Time with per-particle offset
    float t = TIME * 0.25 + v_seed * 50.0;

    // ── BREAK UP THE CIRCLE ──

    // Polar coordinates for radial distortion
    float angle = atan(centered.y, centered.x);

    // Radial noise - distorts the edge irregularly
    float radial_noise = noise(vec2(angle * 3.0 + t, v_seed * 10.0)) * 0.4;
    radial_noise += noise(vec2(angle * 7.0 - t * 0.5, v_seed * 20.0)) * 0.2;

    // Tendril/wispy extensions
    float tendrils = tendril_noise(centered + vec2(t * 0.1), v_seed);

    // Combine for broken edge
    float edge_dist = dist - radial_noise * edge_breakup;
    edge_dist -= (tendrils - 0.5) * tendril_strength * 0.3;

    // Soft falloff with very broken edge
    float shape = 1.0 - smoothstep(0.1, 0.7, edge_dist);

    // Internal variation - not uniform density
    float internal = fbm(centered * noise_scale + vec2(t * 0.15, v_seed * 5.0), 3);
    internal = smoothstep(0.2, 0.7, internal);
    shape *= mix(0.6, 1.0, internal);

    // Extra wisps at edges
    float edge_wisps = fbm(centered * noise_scale * 2.0 + vec2(v_seed * 10.0, t * 0.1), 2);
    float wisp_mask = smoothstep(0.3, 0.6, dist) * smoothstep(0.9, 0.5, dist);
    shape += edge_wisps * wisp_mask * 0.3;

    // ── DEPTH & COLOR ──

    // Mix between light and dark based on depth layer
    vec3 color = mix(smoke_color_dark.rgb, smoke_color_light.rgb, v_depth_layer);

    // Add variation within each particle too
    float color_var = noise(centered * 2.0 + vec2(v_seed * 100.0));
    color *= 0.85 + color_var * 0.3;

    // Darker at edges (subsurface scattering feel)
    color *= mix(0.7, 1.0, 1.0 - smoothstep(0.2, 0.6, dist));

    // ── FINAL ──

    float lifetime_alpha = COLOR.a;
    float alpha = shape * lifetime_alpha * alpha_multiplier;
    alpha *= mix(smoke_color_dark.a, smoke_color_light.a, v_depth_layer);

    if (alpha < 0.02) {
        discard;
    }

    ALBEDO = color;
    ALPHA = alpha;
}
