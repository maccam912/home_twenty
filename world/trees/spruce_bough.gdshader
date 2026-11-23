shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, world_vertex_coords;

uniform sampler2D needles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float height = max(0.0, VERTEX.y - root.y);
	float time = TIME * 1.48 + root.x * 0.12 - root.z * 0.11;
	float gust = 0.67 + 0.33 * sin(TIME * 0.55 + root.z * 0.04);
	float bend = height * height * 0.0013 * sin(time);
	// The last needles bend farther than the stems in the same gust.
	float flutter = (1.0 - UV.y) * gust * (0.037 * sin(time * 2.3 + VERTEX.z * 1.8));
	VERTEX.xz += vec2(0.93, 0.36) * (bend + flutter);
	VERTEX.y += flutter * 0.62;
}
void fragment() {
	vec4 branch = texture(needles, UV);
	ALBEDO = branch.rgb * 0.91;
	ROUGHNESS = 1.0;
	ALPHA = branch.a;
	ALPHA_SCISSOR_THRESHOLD = 0.22;
}
