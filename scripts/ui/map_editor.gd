extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main/main_menu.tscn"
const BOARD_CONFIG_PATH := "res://resources/map/map_editor_board_config.tres"
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")
const GridBoardViewScript := preload("res://scripts/map/grid_board_view.gd")
const BoardConfigScript := preload("res://scripts/map/board_config.gd")
const MapDataScript := preload("res://scripts/map/map_data.gd")
const MapTerrainTypeScript := preload("res://scripts/map/map_terrain_type.gd")

var _board_config: BoardConfig
var _board_view: GridBoardView
var _map_data: MapData
var _file_name_edit: LineEdit
var _status_label: Label
var _load_dialog: FileDialog
var _save_dialog: FileDialog


func _ready() -> void:
	UiThemeScript.apply(self)
	_map_data = MapDataScript.create_filled(MapDataScript.DEFAULT_WIDTH, MapDataScript.DEFAULT_HEIGHT)
	_board_config = _load_board_config()
	_build()
	_apply_map_to_view()


func _load_board_config() -> BoardConfig:
	var loaded := load(BOARD_CONFIG_PATH)
	if loaded is BoardConfig:
		return (loaded as BoardConfig).duplicate(true) as BoardConfig
	push_warning("MapEditor: missing %s, using defaults" % BOARD_CONFIG_PATH)
	var cfg := BoardConfigScript.new()
	cfg.grid_width = MapDataScript.DEFAULT_WIDTH
	cfg.grid_height = MapDataScript.DEFAULT_HEIGHT
	return cfg


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_constant_override("margin_left", 10)
	top_bar.add_theme_constant_override("margin_top", 6)
	top_bar.add_theme_constant_override("margin_right", 10)
	add_child(top_bar)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(top_row)

	var back_btn := Button.new()
	back_btn.text = "返回主菜单"
	back_btn.pressed.connect(_on_back_pressed)
	top_row.add_child(back_btn)

	var title := Label.new()
	title.text = "地图编辑"
	title.add_theme_font_size_override("font_size", 18)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(title)

	top_row.add_child(_spacer())

	var file_label := Label.new()
	file_label.text = "文件名"
	file_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(file_label)

	_file_name_edit = LineEdit.new()
	_file_name_edit.text = "map_001.json"
	_file_name_edit.custom_minimum_size.x = 140.0
	top_row.add_child(_file_name_edit)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_pressed)
	top_row.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "加载"
	load_btn.pressed.connect(_on_load_pressed)
	top_row.add_child(load_btn)

	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("margin_left", 12)
	bottom.add_theme_constant_override("margin_bottom", 8)
	add_child(bottom)

	_status_label = Label.new()
	_status_label.text = "点击格子切换：可走 ↔ 不可走"
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_status_label)

	_load_dialog = FileDialog.new()
	_load_dialog.exclusive = false
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_USERDATA
	_load_dialog.filters = PackedStringArray(["*.json ; JSON 地图"])
	_load_dialog.current_dir = MapDataScript.MAPS_USER_DIR
	_load_dialog.title = "加载地图"
	_load_dialog.file_selected.connect(_on_load_file_selected)
	add_child(_load_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.exclusive = false
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_USERDATA
	_save_dialog.filters = PackedStringArray(["*.json ; JSON 地图"])
	_save_dialog.current_dir = MapDataScript.MAPS_USER_DIR
	_save_dialog.title = "保存地图"
	_save_dialog.file_selected.connect(_on_save_file_selected)
	add_child(_save_dialog)


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _on_cell_clicked(cell: Vector2i) -> void:
	var next := MapTerrainTypeScript.toggle(_map_data.get_cell_vec(cell))
	_map_data.set_cell_vec(cell, next)
	_board_view.set_terrain_cell(cell, next)
	_status_label.text = "本格：%s（再点切换）" % MapTerrainTypeScript.label_for(next)


func _apply_map_to_view() -> void:
	_board_config.grid_width = _map_data.width
	_board_config.grid_height = _map_data.height
	_board_view.setup(_board_config)
	_board_view.set_terrain_cells(_map_data.terrain_dictionary())


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_save_pressed() -> void:
	if not MapDataScript.ensure_maps_dir():
		_status_label.text = "无法创建存档目录"
		return
	var path := MapDataScript.resolve_maps_path(_file_name_edit.text)
	if OS.has_feature("web"):
		_do_save(path)
	else:
		_save_dialog.current_file = path.get_file()
		_save_dialog.popup_centered_ratio(0.55)


func _on_load_pressed() -> void:
	if not MapDataScript.ensure_maps_dir():
		_status_label.text = "无法创建存档目录"
		return
	if OS.has_feature("web"):
		var path := MapDataScript.resolve_maps_path(_file_name_edit.text)
		_do_load(path)
	else:
		_load_dialog.popup_centered_ratio(0.55)


func _on_save_file_selected(path: String) -> void:
	_do_save(path)


func _on_load_file_selected(path: String) -> void:
	_do_load(path)


func _do_save(path: String) -> void:
	if _map_data.save_json_to_path(path):
		_file_name_edit.text = path.get_file()
		_status_label.text = "已保存：%s" % path.get_file()
	else:
		_status_label.text = "保存失败"


func _do_load(path: String) -> void:
	var loaded := MapDataScript.load_json_from_path(path)
	if loaded == null:
		_status_label.text = "加载失败"
		return
	_map_data = loaded
	_file_name_edit.text = path.get_file()
	_apply_map_to_view()
	_status_label.text = "已加载：%s（%d×%d）" % [path.get_file(), _map_data.width, _map_data.height]
