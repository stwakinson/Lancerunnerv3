shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
void fragment() {
 float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 5.0);
 ALBEDO = vec3(0.24, 0.51, 0.85);
 ALPHA = rim * 0.32;
}
