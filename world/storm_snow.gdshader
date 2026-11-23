shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

varying vec3 world_position;
varying vec3 world_normal;
#include "res://world/snow_surface.gdshaderinc"

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// MultiMesh scales each drift to its field dimensions. Transform its normal
	// by the inverse scale so a low shoulder has the same light as the flat.
	mat3 axes = mat3(MODEL_MATRIX);
	vec3 lengths_squared = vec3(dot(axes[0],axes[0]),dot(axes[1],axes[1]),dot(axes[2],axes[2]));
	world_normal = normalize(axes * (NORMAL / lengths_squared));
}

void fragment() {
	NORMAL = normalize(mat3(VIEW_MATRIX) * world_normal);
	vec2 p = world_position.xz;
	ALBEDO = field_snow(p) * snow_contact(p);
	ROUGHNESS = 1.0;
}
