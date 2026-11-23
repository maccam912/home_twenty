shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

varying vec3 world_position;
varying float local_height;
uniform vec4 snow_tint : source_color = vec4(0.82, 0.86, 0.87, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise_at(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_height = VERTEX.y;
}

void fragment() {
	vec2 p = world_position.xz;
	float broad = noise_at(p * 0.10);
	float drift = noise_at(vec2(p.x * 0.65 + p.y * 0.15, p.y * 1.7 - p.x * 0.4));
	float grain = noise_at(p * 17.0);
	float shade = 0.84 + 0.13 * broad + 0.055 * drift + 0.025 * grain;
	ALBEDO = snow_tint.rgb * shade;
	ROUGHNESS = 1.0;
}
