shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, depth_draw_never;
#include "res://ui/crt_signal.gdshaderinc"

uniform sampler2D opaque_scene : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	// Give only the visible enamel a little pre-emphasis before the final CRT
	// pass. One 3D pixel corresponds to one TV line after the picture is enlarged.
	vec2 dx = vec2(0.8 / float(textureSize(opaque_scene, 0).x), 0.0);
	vec3 center = textureLod(opaque_scene, SCREEN_UV, 0.0).rgb;
	vec3 left = textureLod(opaque_scene, SCREEN_UV - dx, 0.0).rgb;
	vec3 right = textureLod(opaque_scene, SCREEN_UV + dx, 0.0).rgb;
	float luma;
	vec3 signal_loss = center - composite_signal(center, left, right, luma);
	ALBEDO = center + clamp(signal_loss * 0.36, vec3(-0.018), vec3(0.018));
	ALPHA = 1.0;
}
