shader_type spatial;
render_mode unshaded;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float hash(vec3 p) { return fract(sin(dot(p, vec3(17.17, 83.13, 29.71))) * 43758.5453); }
void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float sun = smoothstep(-0.35, 0.7, dot(world_normal, normalize(vec3(-0.6, 0.45, 0.65))));
	vec3 colour = mix(vec3(0.25, 0.29, 0.43), vec3(0.96, 0.64, 0.31), sun);
	vec3 cell = floor(world_position / 8.0);
	float patch = hash(cell);
	colour *= 0.93 + floor(patch * 4.0) * 0.02;
	// Sparse dark mineral seams and discrete stone patches preserve a pixel grid.
	if (patch > 0.975) colour = mix(colour, vec3(0.34, 0.30, 0.43), 0.2);
	float haze = smoothstep(350.0, 1700.0, length(VERTEX)) * 0.62;
	ALBEDO = mix(colour, vec3(0.45, 0.45, 0.61), haze);
}
