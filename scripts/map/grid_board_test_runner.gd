extends SceneTree
## 方格棋盘 / 3D 镜头 / 占位单位烟测（Headless）。


const BoardConfigScript := preload("res://scripts/map/board_config.gd")
const GridBoardViewScript := preload("res://scripts/map/grid_board_view.gd")


func _initialize() -> void:
	if not _test_cell_mapping():
		quit(1)
		return
	if not _test_pan_vertical_intuitive():
		quit(1)
		return
	if not _test_view_builds():
		quit(1)
		return
	if not _test_unit_scale_vs_cell():
		quit(1)
		return
	print("GRID_BOARD_OK")
	quit(0)


func _test_unit_scale_vs_cell() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 4
	cfg.grid_height = 4
	cfg.cell_size = 1.0
	cfg.unit_world_height = 0.88
	var host := Control.new()
	host.custom_minimum_size = Vector2(480, 360)
	host.size = Vector2(480, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	var UnitDefScript := preload("res://scripts/units/tactical_unit_def.gd")
	var UnitInstScript := preload("res://scripts/units/tactical_unit_instance.gd")
	var FactionScript := preload("res://scripts/units/tactical_faction.gd")
	var def_path := "res://resources/units/knight.tres"
	if not ResourceLoader.exists(def_path):
		return true
	var def: TacticalUnitDef = load(def_path) as TacticalUnitDef
	if def == null or def.texture_blue == null:
		return true
	var unit: TacticalUnitInstance = UnitInstScript.new(def, FactionScript.Id.PLAYER, Vector2i(1, 1))
	view.sync_tactical_units([unit], Vector2i(-1, -1), [])
	if not view._unit_sprites.has(unit):
		push_error("GridBoardView: unit sprite missing after sync")
		return false
	var spr: Sprite3D = view._unit_sprites[unit] as Sprite3D
	var expected_h := cfg.unit_world_height
	var tex_h := float(def.texture_blue.get_height())
	var expected_pixel := expected_h / tex_h
	if absf(spr.pixel_size - expected_pixel) > 0.0001:
		push_error(
			"GridBoardView: unit pixel_size %.5f != expected %.5f"
			% [spr.pixel_size, expected_pixel]
		)
		return false
	if expected_h > cfg.cell_size * cfg.tile_inset:
		push_error("GridBoardView: unit_world_height should fit inside cell inset")
		return false
	return true


func _test_pan_vertical_intuitive() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	var view := GridBoardViewScript.new()
	view.config = cfg
	view._zoom = 1.0
	var yaw := deg_to_rad(cfg.camera_yaw_deg)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var delta := view.compute_pan_world_delta(Vector2(0.0, -24.0))
	if delta.dot(forward) <= 0.0:
		push_error("GridBoardView: upward drag should pan along +forward (grab-the-map feel)")
		return false
	return true


func _test_cell_mapping() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 6
	cfg.grid_height = 4
	cfg.cell_size = 1.0
	var view := GridBoardViewScript.new()
	view.config = cfg
	for gx in range(cfg.grid_width):
		for gy in range(cfg.grid_height):
			var cell := Vector2i(gx, gy)
			var w := view._cell_to_world(cell, cfg.cell_size)
			var back: Variant = view._world_to_cell(w)
			if back != cell:
				push_error("GridBoardView: cell roundtrip failed %s -> %s" % [cell, back])
				return false
	return true


func _test_view_builds() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 8
	cfg.grid_height = 6
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.custom_minimum_size = Vector2(640, 360)
	host.size = Vector2(640, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(view)
	view.setup(cfg)
	if view.get_child_count() < 1:
		push_error("GridBoardView: missing viewport tree")
		return false
	var camera := _find_camera(view)
	if camera == null:
		push_error("GridBoardView: Camera3D missing")
		return false
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		push_error("GridBoardView: expected orthogonal projection")
		return false
	var units := _find_node_named(view, "Units")
	if units == null:
		push_error("GridBoardView: Units root missing")
		return false
	var local_pos := camera.position
	var elev_deg := rad_to_deg(atan2(local_pos.y, Vector2(local_pos.x, local_pos.z).length()))
	if absf(elev_deg - cfg.camera_pitch_deg) > 1.5:
		push_error("GridBoardView: camera elev %.1f° != pitch %.1f°" % [elev_deg, cfg.camera_pitch_deg])
		return false
	return true


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


func _find_node_named(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find_node_named(child, node_name)
		if found != null:
			return found
	return null
