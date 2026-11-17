shader_type canvas_item;
render_mode unshaded, blend_mix;

// Pure-2D hit flash only. Idle sprites must NOT keep this material (default Sprite2D path).
// flash_amount=1 -> opaque pixels become pure white; 0 -> texture * modulate (same as default).
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Match built-in canvas_item: COLOR already carries modulate/vertex color.
	COLOR *= texture(TEXTURE, UV);
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0, 1.0, 1.0), flash_amount);
}
