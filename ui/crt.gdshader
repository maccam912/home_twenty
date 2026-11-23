shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D picture : hint_screen_texture, repeat_disable, filter_linear;
uniform float line_pitch = 2.0;

void fragment() {
	vec2 dx = vec2(SCREEN_PIXEL_SIZE.x * line_pitch * 0.8, 0.0);
	vec3 center = texture(picture, SCREEN_UV).rgb;
	vec3 left = texture(picture, SCREEN_UV - dx).rgb;
	vec3 right = texture(picture, SCREEN_UV + dx).rgb;

	// Composite video carries less color detail than brightness detail.
	vec3 luma_weights = vec3(0.299, 0.587, 0.114);
	float luma = dot(mix(center, (left + right) * 0.5, 0.16), luma_weights);
	vec3 color_signal = center * 0.54 + left * 0.31 + right * 0.15;
	vec3 phosphor = luma + (color_signal - dot(color_signal, luma_weights)) * 0.96;
	// Bright headlamps and dial lettering spread a little along the scan.
	vec3 bright_neighbor = max(left, right);
	phosphor += 0.065 * max(bright_neighbor - center, vec3(0.0)) * smoothstep(0.65, 1.0, dot(bright_neighbor, luma_weights));

	// Align scanlines to whole output pixels to avoid bands and shimmer during motion.
	float pitch = max(2.0, floor(line_pitch + 0.5));
	float beam = cos(TAU * (FRAGCOORD.y - 0.5) / pitch);
	// A bright phosphor spot fills more of the gap between lines, especially on paper.
	float strength = mix(0.10, 0.035, smoothstep(0.18, 0.85, luma)) * smoothstep(1.0, 2.0, line_pitch);
	COLOR = vec4(phosphor * (1.0 + strength * beam), 1.0);
}
