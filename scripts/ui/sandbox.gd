extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main/main_menu.tscn"
const BOARD_CONFIG_PATH := "res://resources/map/board_config.tres"
const TurnClockScript := preload("res://scripts/core/turn_clock.gd")
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")
const GridBoardViewScript := preload("res://scripts/map/grid_board_view.gd")
const BoardConfigScript := preload("res://scripts/map/board_config.gd")

var _clock: TurnClock
var _turn_label: Label
var _hint_label: Label
var _board_config: BoardConfig
var _board_view: GridBoardView
var _selected_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	UiThemeScript.apply(self)
	_clock = TurnClockScript.new()
	_board_config = _load_board_config()
	_build()
	_refresh()


func _load_board_config() -> BoardConfig:
	var loaded := load(BOARD_CONFIG_PATH)
	if loaded is BoardConfig:
		return (loaded as BoardConfig).duplicate(true) as BoardConfig
	push_warning("Sandbox: missing %s, using defaults" % BOARD_CONFIG_PATH)
	return BoardConfigScript.new()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("121820")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_board_view = GridBoardViewScript.new()
	_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_board_view)
	_board_view.setup(_board_config)
	_board_view.cell_clicked.connect(_on_cell_clicked)

	var top_bar := MarginContainer.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_bar.add_theme_constant_override("margin_left", 10)
	top_bar.add_theme_constant_override("margin_top", 6)
	top_bar.add_theme_constant_override("margin_right", 10)
	top_bar.add_theme_constant_override("margin_bottom", 0)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(top_row)

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 16)
	_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(_turn_label)

	_hint_label = Label.new()
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color("c5d0dc"))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(_hint_label)

	var bottom_bar := MarginContainer.new()
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_bar.add_theme_constant_override("margin_left", 10)
	bottom_bar.add_theme_constant_override("margin_top", 0)
	bottom_bar.add_theme_constant_override("margin_right", 10)
	bottom_bar.add_theme_constant_override("margin_bottom", 8)
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_bar)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_BEGIN
	bottom_bar.add_child(actions)

	var end_turn := Button.new()
	end_turn.text = "结束行动"
	end_turn.custom_minimum_size = Vector2(96, 32)
	end_turn.pressed.connect(_on_end_turn_pressed)
	actions.add_child(end_turn)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 32)
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)


func _refresh() -> void:
	_turn_label.text = "对战 · %s" % _clock.status_text()
	var sel := ""
	if _selected_cell.x >= 0:
		sel = " · 格(%d,%d)" % [_selected_cell.x, _selected_cell.y]
	_hint_label.text = "%dx%d 方格 · 拖拽/滚轮%s" % [
		_board_config.grid_width,
		_board_config.grid_height,
		sel,
	]


func _on_cell_clicked(cell: Vector2i) -> void:
	if not _clock.player_active:
		return
	_selected_cell = cell
	_refresh()


func _on_end_turn_pressed() -> void:
	_clock.end_turn()
	_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
