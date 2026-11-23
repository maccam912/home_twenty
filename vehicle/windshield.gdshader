shader_type spatial;
render_mode cull_disabled, depth_draw_never, unshaded, shadows_disabled;

uniform float frost_amount = 1.0;
uniform float base_tint = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(11.83, 71.17))) * 3741.379);
}

float grain(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 rim = min(uv, vec2(1.0) - uv);
	float fibers = grain(uv * vec2(112.0, 51.0));
	float needles = grain(vec2(uv.x * 240.0 + uv.y * 47.0, uv.y * 44.0));
	float corners = pow(abs(uv.x * 2.0 - 1.0), 2.2);
	float edge = min(rim.x * 2.4, rim.y);
	float extent = (.013 + .058 * corners) * (.45 + .88 * fibers + .32 * needles);
	float frost = 1.0 - smoothstep(extent * .19, extent + .009, edge);
	float grime = .5 * grain(uv * vec2(40.0, 3.0)) + .5 * fibers;
	ALBEDO = mix(vec3(.31, .45, .48), vec3(.80, .87, .86), frost);
	ALPHA = base_tint + .018 * grime + frost_amount * frost * (.16 + .24 * fibers);
}
