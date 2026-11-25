shader_type canvas_item;
uniform float clock = 0.0;
uniform bool rain_enabled = true;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float hearth = exp(-pow(distance(UV, vec2(0.145, 0.52)) * 7.0, 2.0));
	float flicker = sin(clock * 7.7) * 0.018 + sin(clock * 13.3) * 0.012;
	c.rgb *= 1.0 + hearth * flicker;
	// Rain belongs to the glass plane, not the independent city behind it.
	if (c.a < 0.03 && rain_enabled) {
		float column = floor(UV.x * 260.0);
		float streak = step(0.97, fract(UV.x * 260.0));
		float fall = step(0.88, fract(UV.y * 18.0 + clock * (0.55 + fract(column * 0.37) * 0.4)));
		c = mix(c, vec4(0.55, 0.78, 0.90, 0.22), streak * fall);
	}
	COLOR = c;
}
