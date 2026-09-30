// Additive trail strip (bullet trails), same look as the particle material.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D fx_texture : source_color, filter_linear_mipmap;

void fragment() {
	vec4 t = texture(fx_texture, UV);
	ALBEDO = COLOR.rgb * t.rgb;
	ALPHA = COLOR.a * t.a;
}
