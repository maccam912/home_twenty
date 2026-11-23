shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://world/snow_surface.gdshaderinc"

uniform sampler2D deposit_mask : filter_linear, repeat_disable;
uniform vec2 dimensions;
uniform float variation;
varying vec2 across_bay;
varying vec2 ground;

void vertex() {
	across_bay = VERTEX.xz / dimensions + .5;
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.)).xz;
	float depth = textureLod(deposit_mask, across_bay, 0.).r;
	vec2 edge = min(across_bay, 1. - across_bay) * dimensions;
	float crust = noise_at(ground * 1.5 + variation);
	float shoulder = smoothstep(.04, .58 + .32 * crust, min(edge.x, edge.y));
	float pack = noise_at(vec2(across_bay.y * 4.7 + variation, across_bay.x * .9));
	float ridge = .5 + .5 * sin(across_bay.y * 20. + 3. * pack + across_bay.x * 2.);
	VERTEX.y += depth * shoulder * (.23 + .23 * ridge + .38 * pack + .12 * crust);
}

void fragment() {
	if (texture(deposit_mask, across_bay).r < .1) {
		discard;
	}
	// A pushed ridge catches the headlights on its broken, sloping face.
	vec3 normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(normal, VIEW) > 0. ? normal : -normal;
	ALBEDO = field_snow(ground) * mix(vec3(.79, .75, .69), vec3(1.), noise_at(ground * .8));
	ROUGHNESS = 1.;
}
