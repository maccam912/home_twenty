const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);

vec3 composite_signal(vec3 center, vec3 left, vec3 right, out float luma) {
	// Composite video carries less color detail than brightness detail.
	luma = dot(mix(center, (left + right) * 0.5, 0.16), LUMA_WEIGHTS);
	vec3 color_signal = center * 0.54 + left * 0.31 + right * 0.15;
	vec3 phosphor = luma + (color_signal - dot(color_signal, LUMA_WEIGHTS)) * 0.96;
	// Bright headlamps and dial lettering spread a little along the scan.
	vec3 bright_neighbor = max(left, right);
	return phosphor + 0.065 * max(bright_neighbor - center, vec3(0.0)) *
			smoothstep(0.65, 1.0, dot(bright_neighbor, LUMA_WEIGHTS));
}
