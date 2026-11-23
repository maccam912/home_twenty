shader_type spatial;
render_mode diffuse_lambert, specular_disabled, world_vertex_coords;

float hash_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float height = max(0.0, VERTEX.y - root.y);
	float time = TIME * 1.48 + root.x * 0.12 - root.z * 0.11;
	VERTEX.xz += vec2(0.93, 0.36) * height * height * 0.0013 * sin(time);
}
void fragment() {
	vec2 p = vec2(UV.x * 5.0, UV.y * 13.0);
	vec2 id = floor(p);
	vec2 in_cell = fract(p);
	float seed = hash_cell(id);
	float slash = (1.0 - smoothstep(0.12, 0.24, abs(in_cell.y - (0.5 + in_cell.x * 0.17))));
	slash *= smoothstep(0.10, 0.27, in_cell.x) * (1.0 - smoothstep(0.38 + seed * 0.45, 0.90, in_cell.x));
	ALBEDO = COLOR.rgb * (1.0 - 0.69 * slash * step(0.4, seed));
	ROUGHNESS = 1.0;
}
