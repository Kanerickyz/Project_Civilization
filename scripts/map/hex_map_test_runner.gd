extends SceneTree
## 六边地图 / WFC / 迷雾 / 3D 网格烟测（Headless）。


const Terrain := preload("res://scripts/map/terrain_type.gd")
const Hex := preload("res://scripts/map/hex_coords.gd")
const HexMapModelScript := preload("res://scripts/map/hex_map_model.gd")
const MapConfigScript := preload("res://scripts/map/map_config.gd")
const HexMeshBuilderScript := preload("res://scripts/map/hex_mesh_builder.gd")
const HexMapViewScript := preload("res://scripts/map/hex_map_view.gd")


func _initialize() -> void:
	if not _test_hex_roundtrip():
		quit(1)
		return
	if not _test_mesh_builder():
		quit(1)
		return
	if not _test_generate_and_fog():
		quit(1)
		return
	if not _test_view_builds():
		quit(1)
		return
	print("HEX_MAP_OK")
	quit(0)


func _test_hex_roundtrip() -> bool:
	var size := 1.0
	for cell in Hex.cells_in_radius(3):
		var p := Hex.axial_to_pixel(cell, size)
		var back := Hex.pixel_to_axial(p, size)
		if back != cell:
			push_error("HexCoords: roundtrip failed %s -> %s" % [cell, back])
			return false
	return true


func _test_mesh_builder() -> bool:
	var mesh: ArrayMesh = HexMeshBuilderScript.build_prism(1.0, 0.8)
	if mesh == null or mesh.get_surface_count() < 1:
		push_error("HexMeshBuilder: empty mesh")
		return false
	return true


func _test_generate_and_fog() -> bool:
	var cfg: MapConfig = MapConfigScript.new()
	cfg.map_radius = 5
	cfg.wfc_max_retries = 64
	var model: HexMapModel = HexMapModelScript.new(cfg)
	if not model.generate(42):
		push_error("HexMapModel: generation failed seed=42")
		return false
	var expected_cells := Hex.cells_in_radius(cfg.map_radius).size()
	if model.terrains.size() != expected_cells:
		push_error("HexMapModel: terrain count %d != %d" % [model.terrains.size(), expected_cells])
		return false
	for cell in Hex.cells_in_radius(cfg.initial_reveal_radius):
		if not Terrain.is_start_land(model.terrain_at(cell)):
			push_error("HexMapModel: start cell %s not start-land" % cell)
			return false
		if not model.player_revealed(cell):
			push_error("HexMapModel: start cell %s not revealed" % cell)
			return false
	var rim_ocean := 0
	var rim := 0
	for cell in model.all_cells():
		if Hex.cube_distance(cell, Vector2i.ZERO) != cfg.map_radius:
			continue
		rim += 1
		var tid := model.terrain_at(cell)
		if tid != Terrain.Id.OCEAN and tid != Terrain.Id.BEACH:
			push_error("HexMapModel: rim cell %s not coast (%d)" % [cell, tid])
			return false
		if tid == Terrain.Id.OCEAN:
			rim_ocean += 1
	if rim > 0 and float(rim_ocean) / float(rim) < 0.5:
		push_error("HexMapModel: rim ocean ratio too low")
		return false
	# 点邻揭开：取中心旁未揭开邻格。
	var opened := false
	for cell in Hex.neighbors(Vector2i.ZERO):
		var fringe := Hex.neighbors_in_radius(cell, cfg.map_radius)
		for f in fringe:
			if model.try_player_reveal(f):
				opened = true
				break
		if opened:
			break
	if not opened:
		push_error("HexMapModel: expected to reveal a fringe fog cell")
		return false
	return true


func _test_view_builds() -> bool:
	var cfg: MapConfig = MapConfigScript.new()
	cfg.map_radius = 3
	var model: HexMapModel = HexMapModelScript.new(cfg)
	model.generate(7)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.custom_minimum_size = Vector2(640, 360)
	host.size = Vector2(640, 360)
	root.add_child(host)
	var view: HexMapView = HexMapViewScript.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(view)
	view.setup(model)
	if view.get_child_count() < 1:
		push_error("HexMapView: missing viewport tree")
		return false
	var camera := _find_camera(view)
	if camera == null:
		push_error("HexMapView: Camera3D missing")
		return false
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		push_error("HexMapView: expected orthogonal projection")
		return false
	# 仰角应接近配置的 45°（相对水平面），避免「几乎顶视」。
	var local_pos := camera.position
	var elev_deg := rad_to_deg(atan2(local_pos.y, Vector2(local_pos.x, local_pos.z).length()))
	if absf(elev_deg - cfg.camera_pitch_deg) > 1.5:
		push_error("HexMapView: camera elev %.1f° != pitch %.1f°" % [elev_deg, cfg.camera_pitch_deg])
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
