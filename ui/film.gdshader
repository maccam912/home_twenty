shader_type canvas_item;
render_mode unshaded;
uniform float exposure_cold = 0.;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.55); }
void fragment() {
	vec2 uv=UV;
	float edge=length((uv-.5)*vec2(1.05,.8));
	float grain=hash(floor(FRAGCOORD.xy*.68)+floor(TIME*12.));
	float ice=smoothstep(.60-exposure_cold*.31,.77,edge+grain*.05);
	float alpha=.023+smoothstep(.35,.79,edge)*.18;
	COLOR = vec4(vec3(.015,.027,.034)+grain*.09,alpha);
	if (exposure_cold>.08) {
		float frost=ice*exposure_cold*.86;
		COLOR=vec4(mix(COLOR.rgb,vec3(.77,.84,.84),frost),max(alpha,frost));
	}
}
