shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

// Integrate a little light scattered by airborne powder. Stop the ray at the
// first opaque surface so the lamps can't shine through the cab or a building.
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float gust : hint_range(0.0,1.0) = 0.35;
varying vec3 back_face;
varying vec3 eye;

void vertex() {
	back_face = VERTEX;
	eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD,1.0)).xyz;
}

void fragment() {
	vec3 ray = normalize(back_face - eye);
	const vec3 half_extent = vec3(6.8,1.9,10.0);
	vec3 inv_ray = 1.0 / (ray + vec3(0.000001));
	vec3 near_sides = min((-half_extent-eye) * inv_ray,(half_extent-eye) * inv_ray);
	float near_t = max(0.0,max(near_sides.x,max(near_sides.y,near_sides.z)));
	float depth = textureLod(scene_depth,SCREEN_UV,0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV*2.0-1.0,mix(CLIP_SPACE_FAR,1.0,depth),1.0);
	float far_t = min(length(back_face-eye),length(view.xyz)/max(view.w,0.00001));
	float step_length = max(far_t-near_t,0.0)/8.0;
	if (step_length < 0.0001) { discard; }
	float scatter = 0.0;
	for (int i=0;i<8;i++) {
		vec3 sample_pos = eye + ray*(near_t+(float(i)+0.5)*step_length);
		float reach = 10.0-sample_pos.z;
		float side = (abs(sample_pos.x)-.67)/(0.43+.24*reach);
		float above = (sample_pos.y-.20+.075*reach)/(.24+.088*reach);
		float lobe = exp(-1.8*(side*side+above*above));
		float sheet = .82+.18*sin(sample_pos.x*.65+sample_pos.z*.37-TIME*2.3);
		scatter += lobe * sheet * (1.0-smoothstep(4.0,19.0,reach)) * step_length;
	}
	ALBEDO = vec3(.88,.83,.68);
	ALPHA = min(scatter*mix(.009,.018,gust),.16);
}
