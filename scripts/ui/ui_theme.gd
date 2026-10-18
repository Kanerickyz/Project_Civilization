extends RefCounted

const UI_FONT_PATH := "res://resources/ui/ui_font.tres"


static func apply(control: Control) -> void:
	var font := load(UI_FONT_PATH) as Font
	if font == null:
		push_error("UiTheme: missing font %s" % UI_FONT_PATH)
		return
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 20
	control.theme = theme
