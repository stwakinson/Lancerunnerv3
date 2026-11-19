shader_type spatial;
uniform vec3 stone : source_color = vec3(0.25, 0.22, 0.29);
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
 float grain = sin(local_position.x * 4.3 + local_position.y * 3.7 + local_position.z * 5.2) * 0.022;
 float haze = smoothstep(100.0, 850.0, length(VERTEX));
 ALBEDO = (stone + grain) * (1.0 - haze * 0.6);
 ROUGHNESS = 0.96;
 EMISSION = vec3(0.16, 0.18, 0.29) * haze * 0.55;
}
