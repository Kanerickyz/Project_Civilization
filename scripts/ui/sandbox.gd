extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main/main_menu.tscn"
const TurnClockScript := preload("res://scripts/core/turn_clock.gd")
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const PLAYER_CELL := Vector2i(1, 4)
const RIVAL_CELL := Vector2i(6, 1)

var _clock: TurnClock
var _turn_label: Label


func _ready() -> void:
	UiThemeScript.apply(self)
	_clock = TurnClockScript.new()
	_build()
	_refresh()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "文明战棋 · 沙盘占位"
	column.add_child(title)

	_turn_label = Label.new()
	column.add_child(_turn_label)

	var hint := Label.new()
	hint.text = "格子和双方标记不会移动。结束行动只推进回合。"
	column.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for y in GRID_ROWS:
		for x in GRID_COLUMNS:
			grid.add_child(_make_cell(x, y))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)

	var end_turn := Button.new()
	end_turn.text = "结束行动"
	end_turn.pressed.connect(_on_end_turn_pressed)
	actions.add_child(end_turn)

	var back := Button.new()
	back.text = "返回主菜单"
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)


func _make_cell(x: int, y: int) -> Control:
	var cell := ColorRect.new()
	cell.custom_minimum_size = Vector2(56, 56)
	var light := (x + y) % 2 == 0
	cell.color = Color("d7d2c4") if light else Color("b7c4ae")
	var marker := ""
	var cell_position := Vector2i(x, y)
	if cell_position == PLAYER_CELL:
		cell.color = Color("3474b8")
		marker = "我"
	elif cell_position == RIVAL_CELL:
		cell.color = Color("d9892b")
		marker = "彼"
	if marker.is_empty():
		return cell
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = marker
	label.add_theme_color_override("font_color", Color("1e2a32"))
	cell.add_child(label)
	return cell


func _refresh() -> void:
	_turn_label.text = _clock.status_text()


func _on_end_turn_pressed() -> void:
	_clock.end_turn()
	_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
