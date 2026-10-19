shader_type spatial;
// 反壳描边（作为 next_pass）：沿法线外扩、只画背面、无光照深色。GL Compatibility 可用。
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.13, 0.11, 0.09, 1.0);
uniform float outline_width = 0.012;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
