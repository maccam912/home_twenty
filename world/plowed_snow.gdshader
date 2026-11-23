shader_type spatial;
render_mode cull_back;
uniform sampler2D snow_map : filter_linear, repeat_disable;
uniform vec2 origin;
uniform vec2 extent;
varying vec2 at;
float grain(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 12437.127); }
float noise_field(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(grain(i), grain(i+vec2(1,0)),f.x),mix(grain(i+vec2(0,1)),grain(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
	at = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
	vec2 uv = (at - origin) / extent;
	vec2 snow = textureLod(snow_map,uv,0.0).rg;
	float ridges = noise_field(at*vec2(.7,.21))*.04 + .012*sin(at.x*2.3+at.y*.5);
	VERTEX.y += .063 + (1.0-snow.r) * (.125+ridges) + snow.g * .31;
}
void fragment() {
	vec2 uv = (at-origin)/extent;
	vec2 snow = texture(snow_map,uv).rg;
	float dirt = noise_field(at*2.6);
	float drift = noise_field(at*vec2(.55,1.9))-.5;
	vec3 fresh = vec3(.77,.81,.82) + drift*.049;
	vec3 cut = mix(vec3(.28,.33,.35),vec3(.52,.55,.54),dirt);
	ALBEDO = mix(fresh,cut,smoothstep(.02,.97,snow.r)) + snow.g*.055;
	ROUGHNESS = .96;
}
