shader_type sky;

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float longitude_offset = 0.22;
uniform float brightness = 0.8;

// Explicit LOD avoids derivative spikes at the longitude discontinuity.
// A narrow mirrored crossfade makes mismatched generated edges continuous.
// Blend each pole to its own representative colour to suppress pinching.
vec3 wrapped_panorama(vec2 uv) {
 vec3 base = textureLod(panorama, uv, 0.0).rgb;
 float edge = min(uv.x, 1.0 - uv.x);
 float seam = 1.0 - smoothstep(0.0, 0.022, edge);
 vec3 opposite = textureLod(panorama, vec2(1.0 - uv.x, uv.y), 0.0).rgb;
 base = mix(base, (base + opposite) * 0.5, seam);
 float pole = smoothstep(0.94, 1.0, abs(uv.y * 2.0 - 1.0));
 vec3 pole_color = textureLod(panorama, vec2(0.5, uv.y < 0.5 ? 0.001 : 0.999), 0.0).rgb;
 return mix(base, pole_color, pole);
}

void sky() {
 vec3 d = normalize(EYEDIR);
 vec2 uv = vec2(fract(atan(d.x, -d.z) / TAU + 0.5 + longitude_offset), acos(clamp(d.y, -1.0, 1.0)) / PI);
 COLOR = wrapped_panorama(uv) * brightness;
}
