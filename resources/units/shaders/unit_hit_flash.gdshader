shader_type canvas_item;
render_mode unshaded;

// 1 = opaque pixels become pure white; 0 = normal texture * modulate.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = tex.a * COLOR.a;
	vec3 base = tex.rgb * COLOR.rgb;
	COLOR = vec4(mix(base, vec3(1.0, 1.0, 1.0), flash_amount), a);
}
