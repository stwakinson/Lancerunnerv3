shader_type spatial;
render_mode unshaded;

void fragment() {
 float bands = sin(UV.y * 68.0 + sin(UV.x * 24.0) * 1.5) * 0.5 + 0.5;
 float clouds = sin(UV.x * 37.0 + sin(UV.y * 51.0)) * sin(UV.y * 29.0);
 vec3 surface = mix(vec3(0.16, 0.25, 0.30), vec3(0.35, 0.49, 0.53), bands * 0.45 + clouds * 0.12);
 float light = max(dot(normalize(NORMAL), normalize(vec3(-0.6, 0.4, 0.8))), 0.0);
 float atmosphere = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.5);
 ALBEDO = surface * (0.1 + light * 0.9) + vec3(0.12, 0.37, 0.47) * atmosphere * 0.5;
}
