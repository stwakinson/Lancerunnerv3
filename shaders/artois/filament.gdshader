shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float span = 800.0;
uniform vec4 gold : source_color = vec4(1.0, 0.52, 0.09, 1.0);
uniform float density = 0.16;
uniform vec3 ship_position = vec3(0.0);
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.8);
	float mist = 0.55 + 0.25 * sin(UV.y * span * 0.022 + UV.x * 20.0 - TIME * 2.0);
	float pulse = pow(0.5 + 0.5 * sin(UV.y * span * 0.055 - TIME * 7.0), 8.0);
	// Keep the ship silhouette clear when its chase camera is inside the stream.
	float near_ship = smoothstep(22.0, 65.0, distance(world_position, ship_position));
	ALBEDO = gold.rgb * (1.0 + pulse * 0.6);
	float visibility = density > 0.5 ? 1.0 : (0.2 + facing * 0.8);
	ALPHA = near_ship * visibility * density * (0.45 + mist * 0.55 + pulse * 0.25);
}
