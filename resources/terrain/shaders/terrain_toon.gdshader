shader_type spatial;
// 地块 toon 着色：顶点色（sRGB）albedo + 分级明暗；顶点色 alpha 作为世界噪声斑块遮罩。
// 仅用 GL Compatibility / Web 可用特性：无 instance uniform、无屏幕纹理、无 Forward+ 专属内建。
render_mode cull_back, specular_disabled;

uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float shadow_level : hint_range(0.0, 1.0) = 0.42;
uniform float mid_level : hint_range(0.0, 1.0) = 0.74;
uniform float mid_threshold : hint_range(-1.0, 1.0) = 0.12;
uniform float lit_threshold : hint_range(-1.0, 1.0) = 0.55;
uniform float band_softness : hint_range(0.001, 0.3) = 0.04;
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.66, 0.82, 1.0);
uniform vec4 patch_color : source_color = vec4(0.74, 0.62, 0.33, 1.0);
uniform float patch_strength : hint_range(0.0, 1.0) = 0.0;
uniform float patch_scale = 0.38;
uniform float patch_coverage : hint_range(0.0, 1.0) = 0.58;
uniform float patch_edge : hint_range(0.005, 0.5) = 0.06;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.06;
uniform float grain_scale = 9.0;

varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// source_color uniform 已是线性；顶点色先转线性再混合。
	vec3 col = srgb_to_linear(clamp(COLOR.rgb, 0.0, 1.0));
	if (patch_strength > 0.0) {
		vec2 wp = v_world.xz * patch_scale;
		float n = value_noise(wp) * 0.65 + value_noise(wp * 2.3 + 17.0) * 0.35;
		float m = smoothstep(patch_coverage, patch_coverage + patch_edge, n) * patch_strength * COLOR.a;
		col = mix(col, patch_color.rgb, m);
	}
	float g = value_noise(v_world.xz * grain_scale + v_world.y * 3.0) - 0.5;
	col *= 1.0 + g * grain_strength * 2.0;
	ALBEDO = col * albedo_tint.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * ATTENUATION;
	float to_mid = smoothstep(mid_threshold - band_softness, mid_threshold + band_softness, ndl);
	float to_lit = smoothstep(lit_threshold - band_softness, lit_threshold + band_softness, ndl);
	float level = mix(mix(shadow_level, mid_level, to_mid), 1.0, to_lit);
	vec3 tint = mix(shadow_tint.rgb, vec3(1.0), to_mid);
	// 不除 PI：满光面 ≈ 顶点色原值，便于按参考图直接调色。
	DIFFUSE_LIGHT += LIGHT_COLOR * level * tint;
}
