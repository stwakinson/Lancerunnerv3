// Soft additive particle (Unity's URP Particles/Unlit, additive) drawn as a
// camera-facing quad. Size (diameter) comes from INSTANCE_CUSTOM.x; max_screen_size
// caps the on-screen size as a fraction of viewport height, like Unity's Max Particle Size.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/fx_billboard.gdshaderinc"
