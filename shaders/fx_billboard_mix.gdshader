// Same soft particle as fx_billboard, but alpha-blended instead of additive, for
// things that block light (dust) rather than glow (sparks, flames).
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/fx_billboard.gdshaderinc"
