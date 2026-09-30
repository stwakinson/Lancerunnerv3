// Planet surface: Jupiter's bands for color from far away, plus two layers of
// rock detail (normal, ambient occlusion and roughness maps) projected onto the
// sphere from three sides, so craters and bumps appear as you fly closer:
// a crater layer from a distance, and a gravel/rock layer near the ground.
shader_type spatial;

uniform sampler2D global_albedo : source_color, filter_linear_mipmap_anisotropic;

group_uniforms craters;
uniform sampler2D macro_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float macro_tile = 80.0;
uniform float macro_normal_strength = 1.5;
uniform float macro_fade_start = 300.0;
uniform float macro_fade_end = 1500.0;

group_uniforms ground;
uniform sampler2D micro_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D micro_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D micro_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float micro_tile = 8.0;
uniform float micro_normal_strength = 1.2;
uniform float micro_fade_start = 15.0;
uniform float micro_fade_end = 60.0;

group_uniforms look;
uniform float base_roughness = 0.9;
// How strongly the rock's light/dark pattern shows through the planet colors.
uniform float albedo_detail = 1.0;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri_sample(sampler2D s, vec3 p, vec3 w) {
	return texture(s, p.zy) * w.x + texture(s, p.xz) * w.y + texture(s, p.xy) * w.z;
}

// Normal maps may be imported as two channels, so rebuild z.
vec3 unpack_normal(vec4 t, float strength) {
	vec2 xy = (t.xy * 2.0 - 1.0) * strength;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

// Triplanar normal mapping with a "whiteout" blend onto the surface normal n.
vec3 tri_normal(sampler2D s, vec3 p, vec3 n, vec3 w, float strength) {
	vec3 tx = unpack_normal(texture(s, p.zy), strength);
	vec3 ty = unpack_normal(texture(s, p.xz), strength);
	vec3 tz = unpack_normal(texture(s, p.xy), strength);
	tx = vec3(tx.xy + n.zy, tx.z * n.x);
	ty = vec3(ty.xy + n.xz, ty.z * n.y);
	tz = vec3(tz.xy + n.xy, tz.z * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec3 n = normalize(obj_normal);
	vec3 w = tri_weights(n);
	float dist = length(VERTEX);
	float macro_w = 1.0 - smoothstep(macro_fade_start, macro_fade_end, dist);
	float micro_w = 1.0 - smoothstep(micro_fade_start, micro_fade_end, dist);

	vec3 pm = obj_pos / macro_tile;
	vec3 pu = obj_pos / micro_tile;

	// Rock brightness relative to its own average, so the planet keeps Jupiter's colors.
	float macro_avg = max(luma(textureLod(macro_albedo, vec2(0.5), 12.0).rgb), 0.01);
	float micro_avg = max(luma(textureLod(micro_albedo, vec2(0.5), 12.0).rgb), 0.01);
	float macro_shade = luma(tri_sample(macro_albedo, pm, w).rgb) / macro_avg;
	float micro_shade = luma(tri_sample(micro_albedo, pu, w).rgb) / micro_avg;
	float shade = mix(1.0, macro_shade, macro_w * albedo_detail) * mix(1.0, micro_shade, micro_w * albedo_detail);
	ALBEDO = texture(global_albedo, UV).rgb * shade;

	vec3 macro_arm_v = tri_sample(macro_arm, pm, w).rgb;
	vec3 micro_arm_v = tri_sample(micro_arm, pu, w).rgb;
	AO = mix(1.0, macro_arm_v.r, macro_w) * mix(1.0, micro_arm_v.r, micro_w);
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = mix(base_roughness, micro_arm_v.g, micro_w);
	METALLIC = 0.0;

	vec3 bumped = n;
	if (macro_w > 0.001) {
		bumped = normalize(mix(bumped, tri_normal(macro_normal, pm, bumped, w, macro_normal_strength), macro_w));
	}
	if (micro_w > 0.001) {
		bumped = normalize(mix(bumped, tri_normal(micro_normal, pu, bumped, w, micro_normal_strength), micro_w));
	}
	// The planet isn't rotated or scaled, so object space is world space.
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
}
