shader_type spatial;
render_mode cull_disabled;

// The last few steps lose their edges in the blowing snow.
uniform vec4 wool : source_color;
instance uniform float obscured = 0.0;

void fragment() {
	float grain = fract(52.9829189 * fract(dot(floor(FRAGCOORD.xy), vec2(0.06711056, 0.00583715))));
	if (grain < obscured) {
		discard;
	}
	ALBEDO = wool.rgb;
	ROUGHNESS = 0.94;
}
