shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
void fragment() {
 vec2 p = UV - vec2(0.5);
 float r = length(p);
 float core = 1.0 - smoothstep(0.022, 0.045, r);
 float halo = exp(-r * 13.0) * 0.5;
 float streak = exp(-abs(p.y) * 170.0) * exp(-abs(p.x) * 7.0) * 0.35;
 float rays = pow(abs(sin(atan(p.y,p.x) * 6.0)), 14.0) * exp(-r * 24.0) * 0.12;
 ALBEDO = mix(vec3(1.0, 0.47, 0.22), vec3(1.0, 0.95, 0.8), core);
 ALPHA = (core + halo + streak + rays) * (1.0 - smoothstep(0.35, 0.5, r));
}
