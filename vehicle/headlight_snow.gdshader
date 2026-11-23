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
	const vec3 half_extent = vec3(8.5,2.5,14.0);
	vec3 inv_ray = 1.0 / (ray + vec3(0.000001));
	vec3 near_sides = min((-half_extent-eye) * inv_ray,(half_extent-eye) * inv_ray);
	float near_t = max(0.0,max(near_sides.x,max(near_sides.y,near_sides.z)));
	float depth = textureLod(scene_depth,SCREEN_UV,0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV*2.0-1.0,mix(CLIP_SPACE_FAR,1.0,depth),1.0);
	float far_t = min(length(back_face-eye),length(view.xyz)/max(view.w,0.00001));
	float step_length = max(far_t-near_t,0.0)/8.0;
	if (step_length < 0.0001) { discard; }
	float scatter = 0.0;
	vec3 first_sample = eye + ray * (near_t + .5 * step_length);
	vec3 world_start = (MODEL_MATRIX * vec4(first_sample, 1.)).xyz;
	vec3 world_step = mat3(MODEL_MATRIX) * (ray * step_length);
	for (int i=0;i<8;i++) {
		vec3 sample_pos = first_sample + ray * (float(i) * step_length);
		float reach = half_extent.z - sample_pos.z;
		float side = (abs(sample_pos.x) - .66 - .052 * reach) / (.40 + .27 * reach);
		float above = (sample_pos.y + .079 * reach) / (.27 + .12 * reach);
		float lobe = exp(-1.8*(side*side+above*above));
		// Strands of powder travel across the field even when the truck turns.
		vec3 world = world_start + float(i) * world_step;
		float downwind = dot(world.xz, vec2(.96, .28)) - TIME * 8.0;
		float roll = sin(downwind * .63 + world.y * 2.4 + sin(world.z * .85));
		float folds = sin(downwind * 1.2 - world.z * .34 + world.y * 4.5);
		float density = .26 + .74 * smoothstep(-.4, .85, roll * .7 + folds * .3);
		scatter += lobe * density * (1.0 - smoothstep(7., 27., reach)) * step_length;
	}
	ALBEDO = vec3(.97,.94,.84);
	ALPHA = min(scatter * mix(.018,.058,gust), .36);
}
