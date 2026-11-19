shader_type spatial;
render_mode unshaded, fog_disabled;

uniform sampler2D surface_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sunlight = vec3(0.82, 0.55, -0.15);
varying vec3 world_normal;
void vertex() { world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL); }

void fragment() {
 vec3 texture_color = texture(surface_map, UV).rgb;
 float detail = dot(texture_color, vec3(0.4, 0.4, 0.2));
 vec3 surface = mix(vec3(0.06, 0.10, 0.18), vec3(0.52, 0.40, 0.48), detail);
 float sun = dot(normalize(world_normal), normalize(sunlight));
 float day = smoothstep(-0.15, 0.35, sun);
 float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 4.0);
 ALBEDO = surface * (0.08 + day * 0.85) + vec3(0.16, 0.32, 0.55) * rim * (0.12 + day * 0.4);
}
