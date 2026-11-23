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
	float reach = max(0., ahead - 2.86);
	// Paired plow lamps, aimed a little down and out from the top of the blade.
	float side = (abs(across) - .66 - .052 * reach) / (.43 + .36 * reach);
	float height = (dot(delta, truck_up) - 1.53 + .079 * reach) / (.34 + .16 * reach);
	float depth = smoothstep(2.80, 3.65, ahead) * (1. - smoothstep(12., 36., reach));
	float beam = (1. - smoothstep(.34, 1.2, length(vec2(side, height)))) * depth;
	float lamp = 0.;
	for (int i = 0; i < yard_lamps.length(); i++) {
		vec3 diff = p - yard_lamps[i];
		lamp = max(lamp, 1. - smoothstep(0., 28., dot(diff, diff)));
	}
	return vec2(beam, lamp);
}
