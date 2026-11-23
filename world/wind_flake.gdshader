shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://world/snow_light.gdshaderinc"

varying vec3 flake_color;
varying float opacity;

void vertex() {
	vec3 world_center = MODEL_MATRIX[3].xyz;
	vec3 eye = (VIEW_MATRIX * vec4(world_center, 1.)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 velocity = vec3(9. + gust * 5., -2.2, 2.6);
	vec2 streak = (VIEW_MATRIX * vec4(velocity, 0.)).xy;
	float projected = length(streak);
	vec2 along = streak / max(projected, 0.001);
	vec2 across = vec2(-along.y, along.x);
	vec2 light = powder_light(world_center);
	// Fast, near-horizontal grains catch the lamps for a few metres of their flight.
	float exposure = .10 + light.x * .15;
	vec2 drift = VERTEX.y * along * (.40 + exposure * projected);
	VERTEX.xy = size * (VERTEX.x * across * (1. + .28 * light.x) + drift);
	MODELVIEW_MATRIX = mat4(vec4(1.,0.,0.,0.),vec4(0.,1.,0.,0.),vec4(0.,0.,1.,0.),vec4(eye,1.));
	float brightness = max(light.x, light.y);
	flake_color = mix(vec3(.44,.51,.56), vec3(1.0,.97,.86), light.x);
	flake_color = mix(flake_color, vec3(1.,.73,.43), light.y*.8);
	opacity = smoothstep(.8, 2.6, -eye.z) * min(1., .23 + .18*gust + brightness*.76);
	// Keep flakes out of the pickup, even with the camera looking back through the windshield.
	vec3 offset = world_center - truck_position;
	float local_x = dot(offset.xz, vec2(-truck_forward.z, truck_forward.x));
	float local_z = dot(offset.xz, truck_forward.xz);
	if (abs(local_x) < .99 && local_z > -.62 && local_z < 1.24 && offset.y < 2.1) {
		opacity = 0.;
	}
}
void fragment() {
	vec2 coords = (UV-.5)*2.;
	float flake = 1. - smoothstep(.10, 1.0, dot(coords, coords));
	ALBEDO = flake_color;
	ALPHA = flake * opacity;
}
