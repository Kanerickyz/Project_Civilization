extends SceneTree
## 地图 JSON 存读 roundtrip 与编辑器场景烟测。


const MapDataScript := preload("res://scripts/map/map_data.gd")
const MapTerrainTypeScript := preload("res://scripts/map/map_terrain_type.gd")
const GridBoardViewScript := preload("res://scripts/map/grid_board_view.gd")

const GRASS := &"grass"
const WALL := &"wall_straight"


func _initialize() -> void:
	if not _test_roundtrip_json():
		quit(1)
		return
	if not _test_v1_migration():
		quit(1)
		return
	if not _test_unknown_id_fallback():
		quit(1)
		return
	if not _test_bounds_and_errors():
		quit(1)
		return
	if not _test_map_editor_scene_loads():
		quit(1)
		return
	call_deferred("_finish_async")


func _finish_async() -> void:
	await process_frame
	if not await _test_map_editor_cell_click_toggle():
		quit(1)
		return
	print("MAP_EDITOR_OK")
	quit(0)


func _test_roundtrip_json() -> bool:
	if not MapDataScript.ensure_maps_dir():
		push_error("MapEditorTest: cannot create maps dir")
		return false
	var data := MapDataScript.create_filled(8, 8, GRASS)
	data.set_cell(0, 0, WALL)
	data.set_cell(3, 4, WALL)
	data.set_cell(7, 7, GRASS)
	if data.get_cell(0, 0) != WALL or data.get_cell(1, 0) != GRASS:
		push_error("MapEditorTest: set_cell did not store terrain id")
		return false
	var path := MapDataScript.MAPS_USER_DIR.path_join("_test_roundtrip.json")
	if not data.save_json_to_path(path):
		push_error("MapEditorTest: save failed")
		return false
	var loaded := MapDataScript.load_json_from_path(path)
	if loaded == null:
		push_error("MapEditorTest: load failed")
		return false
	if loaded.width != 8 or loaded.height != 8:
		push_error("MapEditorTest: size mismatch")
		return false
	for y in range(8):
		for x in range(8):
			if loaded.get_cell(x, y) != data.get_cell(x, y):
				push_error("MapEditorTest: cell mismatch at %s" % Vector2i(x, y))
				return false
	var dict := loaded.to_dict()
	if str(dict.get("format")) != MapDataScript.FORMAT_ID or MapDataScript.FORMAT_ID != "tactical_map_v2":
		push_error("MapEditorTest: format id mismatch")
		return false
	var raw_text := FileAccess.get_file_as_string(path)
	var raw: Variant = JSON.parse_string(raw_text)
	if raw is not Dictionary or str(raw.get("format")) != "tactical_map_v2":
		push_error("MapEditorTest: saved file should be tactical_map_v2")
		return false
	var raw_cells: Array = raw.get("cells", [])
	if raw_cells.size() != 64 or str(raw_cells[0]) != "wall_straight" or str(raw_cells[1]) != "grass":
		push_error("MapEditorTest: saved cells should be string ids row-major, got %s" % str(raw_cells.slice(0, 2)))
		return false
	if str(raw_cells[4 * 8 + 3]) != "wall_straight":
		push_error("MapEditorTest: saved cell (3,4) should be wall_straight")
		return false
	DirAccess.remove_absolute(path)
	return true


func _test_v1_migration() -> bool:
	var v1 := {
		"format": "tactical_map_v1",
		"width": 3,
		"height": 2,
		"cells": [0, 1, 2, 0, 0, 1],
	}
	var loaded := MapDataScript.from_dict(v1)
	if loaded == null:
		push_error("MapEditorTest: v1 map should load")
		return false
	var expect: Array[StringName] = [GRASS, WALL, WALL, GRASS, GRASS, WALL]
	for i in expect.size():
		var got := loaded.get_cell(i % 3, i / 3)
		if got != expect[i]:
			push_error("MapEditorTest: v1 index %d expected %s got %s" % [i, expect[i], got])
			return false
	if str(loaded.to_dict().get("format")) != "tactical_map_v2":
		push_error("MapEditorTest: v1 map should re-save as v2")
		return false
	var path := MapDataScript.MAPS_USER_DIR.path_join("_test_v1_legacy.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	var from_file := MapDataScript.load_json_from_path(path)
	DirAccess.remove_absolute(path)
	if from_file == null or from_file.get_cell(2, 0) != WALL or from_file.get_cell(0, 1) != GRASS:
		push_error("MapEditorTest: v1 file load/migrate failed")
		return false
	return true


func _test_unknown_id_fallback() -> bool:
	var loaded := MapDataScript.from_dict({
		"format": "tactical_map_v2",
		"width": 2,
		"height": 2,
		"cells": ["grass", "lava_unknown", 7, "wall_straight"],
	})
	if loaded == null:
		push_error("MapEditorTest: v2 with unknown id should still load")
		return false
	var catalog := TerrainCatalog.load_default()
	if loaded.get_cell(1, 0) != catalog.default_id or loaded.get_cell(0, 1) != catalog.default_id:
		push_error("MapEditorTest: unknown terrain should fall back to default")
		return false
	if loaded.get_cell(1, 1) != WALL:
		push_error("MapEditorTest: known id after unknown should be kept")
		return false
	return true


func _test_bounds_and_errors() -> bool:
	var data := MapDataScript.create_filled(4, 3)
	if data.get_cell(0, 0) != GRASS:
		push_error("MapEditorTest: default fill should be grass")
		return false
	for c in [Vector2i(-1, 0), Vector2i(4, 0), Vector2i(0, 3), Vector2i(0, -1)]:
		if data.is_passable(c):
			push_error("MapEditorTest: out of bounds %s must be impassable" % c)
			return false
		if TerrainCatalog.load_default().is_passable(data.get_cell_vec(c)):
			push_error("MapEditorTest: out of bounds id must be impassable")
			return false
	data.set_cell(1, 1, WALL)
	if data.is_passable(Vector2i(1, 1)) or not data.is_passable(Vector2i(0, 0)):
		push_error("MapEditorTest: is_passable mismatch")
		return false
	var dict := data.terrain_dictionary()
	if dict.size() != 12 or dict[Vector2i(1, 1)] != WALL or dict[Vector2i(3, 2)] != GRASS:
		push_error("MapEditorTest: terrain_dictionary mismatch")
		return false
	if MapTerrainTypeScript.next_id(GRASS) != WALL or MapTerrainTypeScript.next_id(WALL) != GRASS:
		push_error("MapEditorTest: catalog cycle should be grass <-> wall_straight")
		return false
	return true


func _test_map_editor_scene_loads() -> bool:
	var path := "res://scenes/main/map_editor.tscn"
	if not ResourceLoader.exists(path):
		push_error("MapEditorTest: missing scene")
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("MapEditorTest: load scene failed")
		return false
	var node := packed.instantiate()
	if node == null:
		push_error("MapEditorTest: instantiate failed")
		return false
	node.free()
	return true


func _test_map_editor_cell_click_toggle() -> bool:
	var host := Control.new()
	host.size = Vector2(852, 393)
	root.add_child(host)
	var packed := load("res://scenes/main/map_editor.tscn") as PackedScene
	if packed == null:
		push_error("MapEditorTest: editor scene load failed")
		return false
	var editor: Control = packed.instantiate() as Control
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.size = host.size
	host.add_child(editor)
	await process_frame
	var board: GridBoardView = _find_board(editor)
	if board == null:
		push_error("MapEditorTest: GridBoardView missing")
		return false
	var cell := Vector2i(4, 4)
	var before: StringName = StringName(board._terrain_cells.get(cell, GRASS))
	if before != GRASS:
		push_error("MapEditorTest: fresh editor cell should be grass, got %s" % before)
		return false
	var clicks: Array = []
	board.cell_clicked.connect(func(c: Vector2i) -> void:
		clicks.append(c)
	)
	var local_pos := board.size * 0.5
	_sim_board_click(board, local_pos)
	if clicks.is_empty():
		push_error("MapEditorTest: cell_clicked not emitted")
		return false
	var after: StringName = StringName(board._terrain_cells.get(cell, GRASS))
	if after != WALL:
		push_error("MapEditorTest: first click should paint wall_straight at %s, got %s" % [cell, after])
		return false
	if editor._map_data.get_cell_vec(cell) != WALL:
		push_error("MapEditorTest: editor map data should match view after click")
		return false
	_sim_board_click(board, local_pos)
	var again: StringName = StringName(board._terrain_cells.get(cell, GRASS))
	if again != GRASS or editor._map_data.get_cell_vec(cell) != GRASS:
		push_error("MapEditorTest: second click should cycle back to grass, got %s" % again)
		return false
	editor.free()
	host.free()
	return true


func _sim_board_click(board: GridBoardView, local_pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = local_pos
	board._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = local_pos
	board._gui_input(release)


func _find_board(node: Node) -> GridBoardView:
	if node.get_script() == GridBoardViewScript:
		return node as GridBoardView
	for child in node.get_children():
		var found := _find_board(child)
		if found != null:
			return found
	return null
