shader_type canvas_item;
uniform float clock = 0.0;
varying vec4 item_tint;
void vertex() { item_tint = COLOR; }
void fragment() {
 vec4 art = texture(TEXTURE, UV) * item_tint;
 float amber = smoothstep(0.06, 0.25, art.r - art.b) * smoothstep(0.25, 0.6, art.r);
 float flicker = sin(clock * 3.1 + UV.x * 71.0) * sin(clock * 1.7 + UV.y * 39.0);
 float wet = smoothstep(0.82, 1.0, UV.y) * sin(UV.x * 130.0 + clock * 1.8);
 art.rgb *= 1.0 + amber * (flicker * 0.035 + wet * 0.02);
 COLOR = art;
}
