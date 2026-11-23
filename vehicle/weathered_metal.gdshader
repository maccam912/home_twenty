shader_type spatial;

uniform vec4 finish : source_color = vec4(0.45, 0.23, 0.19, 1.0);
uniform float wear = 0.26;
uniform float metalness = 0.28;
varying vec3 body_point;
varying vec3 face_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(87.71, 142.29))) * 7481.385);
}

float grain(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	body_point = VERTEX;
	face_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(face_normal);
	vec2 p = n.y > .65 ? body_point.xz : (n.x > .65 ? body_point.zy : body_point.xy);
	float broad = grain(p * vec2(2.3, 3.8) + 5.8);
	float grainy = grain(p * vec2(48.0, 68.0));
	float snow_scuff = smoothstep(.52, .84, broad * .60 + grainy * .40);
	float lower = smoothstep(.20, .55, .26 - body_point.y);
	float salt = wear * snow_scuff * (.42 + .63 * lower);
	vec3 painted = finish.rgb * (.92 + .16 * broad);
	ALBEDO = mix(painted, vec3(.49, .48, .43), salt);
	ROUGHNESS = .68 + .20 * salt + .04 * grainy;
	METALLIC = metalness * (1.0 - salt);
}
