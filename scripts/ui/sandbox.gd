extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main/main_menu.tscn"
const MAP_CONFIG_PATH := "res://resources/map/map_config.tres"
const TurnClockScript := preload("res://scripts/core/turn_clock.gd")
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")
const HexMapModelScript := preload("res://scripts/map/hex_map_model.gd")
const HexMapViewScript := preload("res://scripts/map/hex_map_view.gd")
const MapConfigScript := preload("res://scripts/map/map_config.gd")

var _clock: TurnClock
var _turn_label: Label
var _hint_label: Label
var _map_model: HexMapModel
var _map_view: HexMapView


func _ready() -> void:
	UiThemeScript.apply(self)
	_clock = TurnClockScript.new()
	_map_model = HexMapModelScript.new(_load_map_config())
	_map_model.generate()
	_build()
	_refresh()


func _load_map_config() -> MapConfig:
	var loaded := load(MAP_CONFIG_PATH)
	if loaded is MapConfig:
		return (loaded as MapConfig).duplicate(true) as MapConfig
	push_warning("Sandbox: missing %s, using defaults" % MAP_CONFIG_PATH)
	return MapConfigScript.new()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)

	var title := Label.new()
	title.text = "文明战棋 · 沙盘"
	column.add_child(title)

	_turn_label = Label.new()
	column.add_child(_turn_label)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint_label)

	var map_host := PanelContainer.new()
	map_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_host.custom_minimum_size = Vector2(0, 180)
	column.add_child(map_host)

	_map_view = HexMapViewScript.new()
	_map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_host.add_child(_map_view)
	_map_view.setup(_map_model)
	_map_view.cell_clicked.connect(_on_cell_clicked)

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


func _refresh() -> void:
	_turn_label.text = _clock.status_text()
	var gen_note := "WFC 已生成" if _map_model.generation_ok else "WFC 失败已回退"
	_hint_label.text = "%s · 拖拽浏览 · 点相邻雾格揭开 · 种子 %d" % [gen_note, _map_model.seed_used]


func _on_cell_clicked(cell: Vector2i) -> void:
	if _map_model.config.reveal_only_on_player_turn and not _clock.player_active:
		return
	if _map_model.try_player_reveal(cell):
		_map_view.queue_redraw()


func _on_end_turn_pressed() -> void:
	_clock.end_turn()
	_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
