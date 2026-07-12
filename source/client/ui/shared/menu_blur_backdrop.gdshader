shader_type canvas_item;

// Frosted-glass menu backdrop (BotW-style): blurs whatever is drawn behind
// the menu, then tints it with dim_color (alpha = tint strength). Drop the
// material on a full-rect backdrop ColorRect — the rect's own color becomes
// the no-shader fallback and is ignored while the material is active.
//
// The blur is the mipmap trick: sampling the screen texture at a high LOD
// costs 4 texture reads total, no gaussian loop, and works on the
// GL Compatibility renderer (desktop / mobile / web).

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0) = 2.5;
uniform vec4 dim_color : source_color = vec4(0.073, 0.082, 0.122, 0.6);

void fragment() {
	// 4 diagonal taps half a (LOD-scaled) texel apart smooth out the blocky
	// bilinear squares a single high-LOD sample would show.
	vec2 px = SCREEN_PIXEL_SIZE * exp2(blur_lod);
	vec3 blurred = (
		textureLod(screen_texture, SCREEN_UV + px * vec2(0.5, 0.5), blur_lod).rgb +
		textureLod(screen_texture, SCREEN_UV + px * vec2(-0.5, 0.5), blur_lod).rgb +
		textureLod(screen_texture, SCREEN_UV + px * vec2(0.5, -0.5), blur_lod).rgb +
		textureLod(screen_texture, SCREEN_UV + px * vec2(-0.5, -0.5), blur_lod).rgb
	) * 0.25;
	COLOR = vec4(mix(blurred, dim_color.rgb, dim_color.a), 1.0);
}
