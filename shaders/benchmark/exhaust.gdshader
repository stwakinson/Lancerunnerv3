shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
void fragment() {
 float centre = pow(max(0.0, 1.0 - abs(UV.x * 2.0 - 1.0)), 2.0);
 ALBEDO = mix(vec3(0.12, 0.47, 1.0), vec3(0.78, 0.95, 1.0), pow(centre, 4.0));
 ALPHA = centre * pow(1.0 - UV.y, 1.4) * 0.85;
}
