shader_type sky;
uniform vec4 horizon : source_color = vec4(.19,.24,.28,1.);
uniform vec4 ground_haze : source_color = vec4(.29,.345,.385,1.);
uniform vec4 ceiling : source_color = vec4(.12,.16,.21,1.);
uniform vec4 cloud_shadow : source_color = vec4(.07,.105,.14,1.);
float h(vec2 p) {
	return fract(sin(dot(p,vec2(127.1, 311.7)))*43758.5453);
}
float cloud(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	vec2 u=f*f*(3.-2.*f);
	return mix(mix(h(i),h(i+vec2(1.,0.)),u.x),mix(h(i+vec2(0.,1.)),h(i+vec2(1.)),u.x),u.y);
}
void sky() {
	float rise=max(0.,EYEDIR.y);
	vec2 p=EYEDIR.xz/(rise+.18);
	p.x+=p.y*.31;
	p*=vec2(1.05,1.4);
	float masses=cloud(p)*.62 + cloud(p*2.3+5.)*.26 + cloud(p*5.4-15.)*.12;
	vec3 clouds=mix(ceiling.rgb,cloud_shadow.rgb,smoothstep(.21,.73,masses));
	vec3 overcast = mix(horizon.rgb,clouds,smoothstep(-.02,.53,rise));
	// Blown powder lightens the bottom few degrees of sky across the open flats.
	COLOR = mix(ground_haze.rgb,overcast,smoothstep(.004,.069+.024*masses,rise));
}
