// Shared body of the particle billboard shaders (see fx_billboard*.gdshader).

uniform sampler2D fx_texture : source_color, filter_linear_mipmap;
uniform float max_screen_size = 0.5;
// When set, instances wrap around the camera inside a box this size (endless starfield).
uniform vec3 wrap_size = vec3(0.0);

void vertex() {
	// Same billboard setup Godot's BaseMaterial3D uses for particles.
	vec4 center = MODEL_MATRIX[3];
	if (wrap_size.x > 0.0) {
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		center.xyz = cam + mod(center.xyz - cam + wrap_size * 0.5, wrap_size) - wrap_size * 0.5;
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], center);
	float depth = max(-MODELVIEW_MATRIX[3].z, 0.001);
	float size = min(INSTANCE_CUSTOM.x, max_screen_size * 2.0 * depth / abs(PROJECTION_MATRIX[1][1]));
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec4 t = texture(fx_texture, UV);
	ALBEDO = COLOR.rgb * t.rgb;
	ALPHA = COLOR.a * t.a;
}
