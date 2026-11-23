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

vec3 field_snow(vec2 p) {
	// Long tongues of wind-packed snow stay visible beyond the fine surface grain.
	vec2 wind = vec2(dot(p,vec2(.95,.31)), dot(p,vec2(-.31,.95)));
	float pack = noise_at(vec2(wind.x*.041,wind.y*.33) + noise_at(p*.047)*1.2);
	float broad = noise_at(p * .065);
	float drift = noise_at(vec2(p.x * 0.65 + p.y * 0.15, p.y * 1.7 - p.x * 0.4));
	float grain = noise_at(p * 17.0);
	float shade = .80 + .16 * broad + .13 * pack + .05 * drift + .022 * grain;
	return snow_tint.rgb * shade;
}

uniform vec4 ground_contacts;

// Diffuse occlusion beneath the tank saddles and the mailbox timber.
float snow_contact(vec2 p) {
	vec2 d = p - ground_contacts.xy;
	vec2 saddle = vec2((abs(d.x)-1.26)/.46,d.y/.99);
	vec2 belly = d / vec2(2.25,1.18);
	float feet = 1. - smoothstep(.38,1.18,dot(saddle,saddle));
	float under_tank = 1. - smoothstep(.22,1.18,dot(belly,belly));
	vec2 post = (p-ground_contacts.zw) / vec2(.225,.255);
	float timber = 1. - smoothstep(.05,1.,dot(post,post));
	return 1. - max(.21*feet + .25*under_tank,.29*timber);
}
