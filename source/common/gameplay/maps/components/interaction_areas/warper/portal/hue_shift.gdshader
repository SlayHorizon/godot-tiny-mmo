shader_type canvas_item;
// Full HSV recolor: rotates hue by [hue_offset] (turns, 0..1) and SCALES saturation +
// value by [sat_scale]/[val_scale] — scaling (not overwriting) preserves the art's own
// shading, so a bright core stays brighter than the rim while a dark target color still
// yields a genuinely dark sprite. Plain modulate can't do any of this (it multiplies
// channels: purple x green = murk). First consumer: Portal. Generic — reuse anywhere.

uniform float hue_offset : hint_range(0.0, 1.0) = 0.0;
uniform float sat_scale : hint_range(0.0, 4.0) = 1.0;
uniform float val_scale : hint_range(0.0, 4.0) = 1.0;

// Standard Sam Hocevar RGB<->HSV conversions.
vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	// COLOR here = texture sample * modulate, so modulate keeps working on top.
	vec3 hsv = rgb_to_hsv(COLOR.rgb);
	hsv.x = fract(hsv.x + hue_offset);
	hsv.y = clamp(hsv.y * sat_scale, 0.0, 1.0);
	hsv.z = clamp(hsv.z * val_scale, 0.0, 1.0);
	COLOR.rgb = hsv_to_rgb(hsv);
}
