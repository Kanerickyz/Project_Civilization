extends RefCounted

const FONT_PATH := "res://assets/fonts/DroidSansFallbackFull.ttf"


static func apply(control: Control) -> void:
	var font := load(FONT_PATH) as Font
	if font == null:
		push_error("UiTheme: missing font %s" % FONT_PATH)
		return
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 20
	control.theme = theme
