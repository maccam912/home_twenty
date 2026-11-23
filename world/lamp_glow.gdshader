shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 lamp_color : source_color = vec4(1.0, .69, .38, 1.);
uniform float strength = .6;
uniform float downward = 0.;
varying float fog_loss;
void vertex() {
	vec3 eye = (VIEW_MATRIX * MODEL_MATRIX[3]).xyz;
	MODELVIEW_MATRIX = mat4(vec4(1.,0.,0.,0.),vec4(0.,1.,0.,0.),vec4(0.,0.,1.,0.),vec4(eye,1.));
	fog_loss = exp(-.026 * length(eye));
}
void fragment() {
	vec2 p = (UV-.5)*2.;
	p.y *= mix(1.0, .78, downward * smoothstep(0.0,.45,p.y));
	float radius = length(p);
	float diffusion = exp(-5.6*radius) * (1.-smoothstep(.62,1.,radius));
	ALBEDO = lamp_color.rgb;
	ALPHA = diffusion * strength * fog_loss;
}
