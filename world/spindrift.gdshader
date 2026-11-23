shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://world/snow_light.gdshaderinc"

uniform float storm_seconds = 0.0;
varying vec3 at;
varying vec3 sheet_normal;

float h(vec2 p) {
	return fract(sin(dot(p,vec2(41.7, 98.2)))*14357.3);
}
float wind_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p); f = f*f*(3.-2.*f);
	return mix(mix(h(i),h(i+vec2(1.,0.)),f.x),mix(h(i+vec2(0.,1.)),h(i+vec2(1.)),f.x),f.y);
}
void vertex() {
	at = (MODEL_MATRIX * vec4(VERTEX,1.)).xyz;
	sheet_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
	float t = storm_seconds;
	float crossfield = at.x * .94 + at.z * .34;
	float wake = at.z + at.x*.11;
	vec2 drift = vec2(crossfield - 5.*t, wake*.8 + at.y*2. - .32*t);
	float eddy = wind_noise(drift*vec2(.29, .81));
	float grains = wind_noise(drift*vec2(.71,1.51) + vec2(.35*t, 0.));
	float boundary = smoothstep(0., .18, UV.x)*(1.-smoothstep(.76,1.,UV.x));
	float curl = sin(at.x*.34-t*1.4+wake*.7)*.06 + eddy*.22;
	float vertical = 1.-smoothstep(.04,.65+.25*gust, abs(UV.y - (.26+curl)) * 1.85);
	float breathing = .18 + .82*smoothstep(.26,.74,wind_noise(vec2(wake*.092 - .18*t,crossfield*.065 - .25*t)));
	float edging = smoothstep(0.,.09,UV.y)*(1.-smoothstep(.79,1.,UV.y));
	float mask = edging * boundary * vertical * smoothstep(.25,.74,eddy*.74+grains*.26)*breathing;
	vec2 illumination = powder_light(at);
	vec3 mist = mix(vec3(.38,.45,.49), vec3(.76,.72,.62), illumination.x);
	ALBEDO = mix(mist, vec3(.86,.63,.40), illumination.y*.66);
	vec3 eye = CAMERA_POSITION_WORLD - at;
	float incidence = abs(dot(normalize(eye),sheet_normal));
	float reveal = smoothstep(.13,.52,incidence)*smoothstep(1.1,4.,length(eye));
	ALPHA = reveal*mask*(.15+.44*gust+.18*max(illumination.x,illumination.y));
}
