// Equirectangular sky sampled with the same mapping as Unity's Skybox/Panoramic,
// so the galactic core sits straight ahead of the starting camera like it did there.
shader_type sky;

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float exposure = 1.0;

void sky() {
	vec3 d = normalize(EYEDIR);
	// Godot's forward is -Z, Unity's is +Z.
	float lon = atan(-d.z, d.x);
	float lat = acos(clamp(d.y, -1.0, 1.0));
	vec2 uv = vec2(0.5 - lon / TAU, lat / PI);
	COLOR = textureLod(panorama, uv, 0.0).rgb * exposure;
}
