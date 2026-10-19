extends SceneTree
## 地图 JSON 存读 roundtrip 与编辑器场景烟测。


const MapDataScript := preload("res://scripts/map/map_data.gd")
const MapTerrainTypeScript := preload("res://scripts/map/map_terrain_type.gd")
const GridBoardViewScript := preload("res://scripts/map/grid_board_view.gd")


func _initialize() -> void:
	if not _test_roundtrip_json():
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
	var data := MapDataScript.create_filled(8, 8, MapTerrainTypeScript.Id.WALKABLE)
	data.set_cell(0, 0, MapTerrainTypeScript.Id.BLOCKED)
	data.set_cell(3, 4, MapTerrainTypeScript.Id.BLOCKED)
	data.set_cell(7, 7, MapTerrainTypeScript.Id.WALKABLE)
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
	if str(dict.get("format")) != MapDataScript.FORMAT_ID:
		push_error("MapEditorTest: format id mismatch")
		return false
	DirAccess.remove_absolute(path)
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
	var before: int = int(board._terrain_cells.get(cell, MapTerrainTypeScript.Id.WALKABLE))
	var clicks: Array = []
	board.cell_clicked.connect(func(c: Vector2i) -> void:
		clicks.append(c)
	)
	var local_pos := board.size * 0.5
	_sim_board_click(board, local_pos)
	if clicks.is_empty():
		push_error("MapEditorTest: cell_clicked not emitted")
		return false
	var after: int = int(board._terrain_cells.get(cell, MapTerrainTypeScript.Id.WALKABLE))
	if after == before:
		push_error("MapEditorTest: terrain did not toggle at %s" % cell)
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
