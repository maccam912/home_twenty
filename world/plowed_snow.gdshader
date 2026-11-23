shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://world/snow_surface.gdshaderinc"

uniform vec4 footprints[5];
uniform sampler2D snow_map : filter_linear, repeat_disable;
uniform vec2 origin;
uniform vec2 extent;
varying vec2 at;
varying float road_weight;

// Overlapping half-feathers add to a full surface wherever road rectangles meet.
float shoulder_weight(vec2 p) {
	float coverage = 0.;
	float width = .94 + .18*sin(p.x*.72+p.y*.81) + .15*sin(p.x*1.43-p.y*.33);
	for (int i=0; i<footprints.length(); i++) {
		vec2 inset = min(p - footprints[i].xy, footprints[i].zw - p);
		vec2 blend = smoothstep(vec2(-width), vec2(width), inset);
		coverage += blend.x * blend.y;
	}
	return smoothstep(.5,1.,coverage);
}

void vertex() {
	at = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
	vec2 uv = (at - origin) / extent;
	vec2 snow = textureLod(snow_map,uv,0.0).rg;
	float ridges = noise_at(at*vec2(.7,.21))*.04 + .012*sin(at.x*2.3+at.y*.5);
	road_weight = shoulder_weight(at);
	VERTEX.y += .003 + road_weight * (.06 + (1.0-snow.r)*(.125+ridges) + snow.g*.31);
}
void fragment() {
	vec2 uv = (at-origin)/extent;
	vec2 snow = texture(snow_map,uv).rg;
	float dirt = noise_at(at*2.6);
	float drift = noise_at(at*vec2(.55,1.9))-.5;
	vec3 fresh = vec3(.77,.81,.82) + drift*.049;
	vec3 cut = mix(vec3(.28,.33,.35),vec3(.52,.55,.54),dirt);
	vec3 road = mix(fresh,cut,smoothstep(.02,.97,snow.r)) + snow.g*.055;
	if (road_weight < .999) {
		road = mix(field_snow(at),road,road_weight);
	}
	ALBEDO = road * snow_contact(at);
	ROUGHNESS = .96;
}
