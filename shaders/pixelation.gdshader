shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Target resolution - 144p would be roughly 256x144 for 16:9
uniform vec2 target_resolution = vec2(256.0, 144.0);

// Color depth reduction (lower = more posterized/splotchy)
uniform float color_levels : hint_range(2.0, 32.0) = 8.0;

// Blend with original (0.0 = full effect, 1.0 = no effect)
uniform float blend : hint_range(0.0, 1.0) = 0.0;

// Enable/disable color quantization
uniform bool quantize_colors = true;

void fragment() {
    // Snap UV to block grid (pixelation)
    vec2 block_uv = floor(SCREEN_UV * target_resolution) / target_resolution;

    // Sample the screen at the snapped position
    vec3 col = textureLod(screen_texture, block_uv, 0.0).rgb;

    // Optional: reduce color depth for extra compression artifact look
    if (quantize_colors) {
        col = floor(col * color_levels) / color_levels;
    }

    // Get original color for blending
    vec3 original = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

    // Blend between effect and original
    COLOR.rgb = mix(col, original, blend);
    COLOR.a = 1.0;
}
