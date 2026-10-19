shader_type spatial;
// 地块 toon 着色：顶点色（sRGB）albedo + 分级明暗；顶点色 alpha 作为草地手绘层遮罩（色块 / 土斑 / 笔触）。
// 仅用 GL Compatibility / Web 可用特性：无 instance uniform、无屏幕纹理、无 Forward+ 专属内建。
render_mode cull_back, specular_disabled;

uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float shadow_level : hint_range(0.0, 1.0) = 0.42;
uniform float mid_level : hint_range(0.0, 1.0) = 0.74;
uniform float mid_threshold : hint_range(-1.0, 1.0) = 0.12;
uniform float lit_threshold : hint_range(-1.0, 1.0) = 0.55;
uniform float band_softness : hint_range(0.001, 0.3) = 0.04;
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.66, 0.82, 1.0);
// 投影里的明暗级（ATTENUATION 拉到该级，冷色 shadow_tint）。
uniform float cast_shadow_level : hint_range(0.0, 1.0) = 0.55;
// 土斑。
uniform vec4 patch_color : source_color = vec4(0.74, 0.62, 0.33, 1.0);
uniform float patch_strength : hint_range(0.0, 1.0) = 0.0;
uniform float patch_scale = 0.38;
uniform float patch_coverage : hint_range(0.0, 1.0) = 0.58;
uniform float patch_edge : hint_range(0.005, 0.5) = 0.06;
// 深浅草色块（手绘色块分层）。
uniform vec4 block_color : source_color = vec4(0.42, 0.52, 0.22, 1.0);
uniform float block_strength : hint_range(0.0, 1.0) = 0.0;
uniform float block_scale = 0.9;
uniform float block_coverage : hint_range(0.0, 1.0) = 0.55;
// 每格整体明暗差（格心哈希）。
uniform float cell_variation : hint_range(0.0, 0.3) = 0.0;
// 方向性笔触。
uniform float stroke_strength : hint_range(0.0, 0.3) = 0.0;
uniform vec2 stroke_scale = vec2(5.0, 22.0);
uniform float grain_strength : hint_range(0.0, 0.3) = 0.06;
uniform float grain_scale = 9.0;

varying vec3 v_world;
varying float v_cell_rand;

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

float fbm2(vec2 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.3 + 17.0) * 0.35;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cell_rand = hash21(MODEL_MATRIX[3].xz * 0.731 + 3.17);
}

void fragment() {
	// source_color uniform 已是线性；顶点色先转线性再混合。
	vec3 col = srgb_to_linear(clamp(COLOR.rgb, 0.0, 1.0));
	float mask = COLOR.a;
	vec2 wp = v_world.xz;
	if (block_strength > 0.0) {
		float nb = fbm2(wp * block_scale + 41.0);
		float mb = smoothstep(block_coverage, block_coverage + 0.08, nb) * block_strength * mask;
		col = mix(col, block_color.rgb, mb);
	}
	if (patch_strength > 0.0) {
		float n = fbm2(wp * patch_scale);
		float m = smoothstep(patch_coverage, patch_coverage + patch_edge, n) * patch_strength * mask;
		col = mix(col, patch_color.rgb, m);
	}
	if (stroke_strength > 0.0) {
		// 斜向拉长噪声模拟笔触。
		vec2 sp = vec2(wp.x + wp.y, wp.x - wp.y) * stroke_scale;
		col *= 1.0 + (value_noise(sp) - 0.5) * stroke_strength * 2.0 * mask;
	}
	col *= 1.0 + (v_cell_rand - 0.5) * cell_variation * 2.0 * mask;
	float g = value_noise(wp * grain_scale + v_world.y * 3.0) - 0.5;
	col *= 1.0 + g * grain_strength * 2.0;
	ALBEDO = col * albedo_tint.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float to_mid = smoothstep(mid_threshold - band_softness, mid_threshold + band_softness, ndl);
	float to_lit = smoothstep(lit_threshold - band_softness, lit_threshold + band_softness, ndl);
	float level = mix(mix(shadow_level, mid_level, to_mid), 1.0, to_lit);
	// 投影单独成一级，避免硬黑；与背光面取较暗者。
	float shadow_mix = 1.0 - clamp(ATTENUATION, 0.0, 1.0);
	level = mix(level, min(level, cast_shadow_level), shadow_mix);
	vec3 tint = mix(shadow_tint.rgb, vec3(1.0), to_mid * (1.0 - shadow_mix));
	// 不除 PI：LIGHT_COLOR 已含 PI，满光面 ≈ albedo × key_energy × PI；整体亮度按 BoardLook.key_energy 调。
	DIFFUSE_LIGHT += LIGHT_COLOR * level * tint;
}
