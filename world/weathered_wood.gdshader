shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec4 paint_color : source_color = vec4(0.49, 0.51, 0.47, 1.0);
uniform bool vertical_boards = false;
uniform float board_width = 0.23;
varying vec3 world_position;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(43.23, 17.13))) * 43758.5453);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float across = world_position.x + world_position.z;
	float course = (vertical_boards ? across : world_position.y) / board_width;
	float stroke = vertical_boards ? world_position.y : across;
	float groove = 1.0 - smoothstep(0.0, 0.095 + fwidth(course), min(fract(course), 1.0 - fract(course)));
	float board = hash(vec2(floor(course), 19.0));
	float wear = hash(vec2(floor(course * 8.0), floor(stroke * 0.65)));
	float filter_width = smoothstep(0.65, 0.06, fwidth(course));
	ALBEDO = paint_color.rgb * (0.97 + (board - 0.5) * 0.13 + (wear - 0.5) * 0.042 - groove * 0.26 * filter_width);
	ROUGHNESS = 0.97;
}
