uniform vec3 truck_position = vec3(0., 0., 44.);
uniform vec3 truck_forward = vec3(0., 0., -1.);
uniform vec3 truck_up = vec3(0., 1., 0.);
uniform vec3 yard_lamps[6];
uniform float gust = 0.0;

// Light scattered by airborne powder in the low beams and around the property lights.
vec2 powder_light(vec3 p) {
	vec3 delta = p - truck_position;
	float ahead = dot(delta, truck_forward);
	float across = dot(delta, cross(truck_forward, truck_up));
	float cone = max(0., ahead - 2.5);
	float spread = 1.05 + cone * .30;
	float side = 1. - smoothstep(spread * .55, spread, abs(across));
	float height = abs(dot(delta, truck_up) - (1.38 - .05 * cone));
	float depth = smoothstep(2.4, 4.0, ahead) * (1. - smoothstep(7., 21., ahead));
	float beam = side * depth * (1. - smoothstep(.65, 1.0 + .1 * cone, height));
	float lamp = 0.;
	for (int i = 0; i < yard_lamps.length(); i++) {
		vec3 diff = p - yard_lamps[i];
		lamp = max(lamp, 1. - smoothstep(0., 28., dot(diff, diff)));
	}
	return vec2(beam, lamp);
}
