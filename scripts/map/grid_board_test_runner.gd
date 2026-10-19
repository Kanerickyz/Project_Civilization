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
	if not _test_overlay_planes():
		quit(1)
		return
	if not _test_terrain_meshes_and_orientation():
		quit(1)
		return
	if not _test_terrain_mesh_dimensions():
		quit(1)
		return
	if not _test_board_look_and_unit_blob():
		quit(1)
		return
	if not _test_grass_billboard_props():
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
	view.sync_tactical_units([unit], Vector2i(-1, -1), [], [])
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


func _test_board_look_and_unit_blob() -> bool:
	var cfg := (load("res://resources/map/board_config.tres") as BoardConfig).duplicate() as BoardConfig
	if cfg.look == null:
		push_error("GridBoardView: board_config.tres should reference a BoardLook")
		return false
	var look := cfg.look
	var host := Control.new()
	host.size = Vector2(480, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	if view._key_light == null or view._environment == null:
		push_error("GridBoardView: key light / environment missing after setup")
		return false
	if view._key_light.shadow_enabled != look.shadow_active():
		push_error("GridBoardView: key light shadow should follow BoardLook.shadow_active()")
		return false
	if not view._key_light.light_color.is_equal_approx(look.key_color):
		push_error("GridBoardView: key light color should come from BoardLook")
		return false
	if view._environment.adjustment_enabled != look.post_adjust_active():
		push_error("GridBoardView: environment adjustment should follow BoardLook.post_adjust_active()")
		return false
	if not is_equal_approx(view._environment.adjustment_saturation, look.adjust_saturation):
		push_error("GridBoardView: saturation should come from BoardLook")
		return false
	var web_look := look.duplicate() as BoardLook
	web_look.shadow_enabled = true
	web_look.shadow_on_web = false
	web_look.post_adjust_enabled = true
	web_look.post_adjust_on_web = false
	if not web_look.shadow_active(false) or web_look.shadow_active(true):
		push_error("BoardLook: shadow should stay on natively and fall back off on Web")
		return false
	if not web_look.post_adjust_active(false) or web_look.post_adjust_active(true):
		push_error("BoardLook: post adjust should stay on natively and fall back off on Web")
		return false
	var def := load("res://resources/units/knight.tres") as TacticalUnitDef
	if def == null:
		push_error("GridBoardView: knight.tres missing for foot blob test")
		return false
	var UnitInstScript := preload("res://scripts/units/tactical_unit_instance.gd")
	var FactionScript := preload("res://scripts/units/tactical_faction.gd")
	var unit: TacticalUnitInstance = UnitInstScript.new(def, FactionScript.Id.PLAYER, Vector2i(1, 1))
	view.sync_tactical_units([unit], Vector2i(-1, -1), [], [])
	var spr := view._unit_sprites[unit] as Sprite3D
	if spr.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		push_error("GridBoardView: billboard unit should not cast a real shadow")
		return false
	if not view._unit_blobs.has(unit):
		push_error("GridBoardView: unit foot blob missing")
		return false
	var blob := view._unit_blobs[unit] as MeshInstance3D
	if blob.get_parent() == spr:
		push_error("GridBoardView: foot blob must not be a child of the billboard sprite")
		return false
	view._process(0.0)
	if absf(blob.position.x - spr.position.x) > 0.001 or absf(blob.position.z - spr.position.z) > 0.001:
		push_error("GridBoardView: foot blob should follow the sprite on the ground plane")
		return false
	if blob.position.y <= cfg.tile_height or blob.position.y > cfg.tile_height + 0.05:
		push_error("GridBoardView: foot blob y=%.3f should sit just above grass top" % blob.position.y)
		return false
	spr.scale = Vector3.ONE * 0.5
	spr.modulate.a = 0.3
	view._process(0.0)
	if absf(blob.scale.x - 0.5) > 0.001:
		push_error("GridBoardView: foot blob should follow sprite scale")
		return false
	if blob.visible:
		push_error("GridBoardView: foot blob should hide while the sprite fades")
		return false
	view.sync_tactical_units([], Vector2i(-1, -1), [], [])
	if view._unit_blobs.has(unit) or not blob.is_queued_for_deletion():
		push_error("GridBoardView: foot blob should be freed with its unit")
		return false
	return true


func _test_overlay_planes() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 4
	cfg.grid_height = 4
	var host := Control.new()
	host.size = Vector2(480, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	var sel := Vector2i(0, 0)
	var move := Vector2i(1, 1)
	var atk := Vector2i(2, 1)
	var plain := Vector2i(3, 3)
	view.sync_tactical_units([], Vector2i(-1, -1), [], [])
	for cell in view._overlay_nodes.keys():
		if (view._overlay_nodes[cell] as MeshInstance3D).visible:
			push_error("GridBoardView: overlay %s should be hidden without highlight" % cell)
			return false
	view.sync_tactical_units([], sel, [move], [atk])
	var colors: Array[Color] = []
	for cell in [sel, move, atk]:
		var ov: MeshInstance3D = view._overlay_nodes[cell] as MeshInstance3D
		if not ov.visible:
			push_error("GridBoardView: overlay %s should be visible" % cell)
			return false
		var mat := ov.material_override as StandardMaterial3D
		if mat == null:
			push_error("GridBoardView: overlay %s missing material" % cell)
			return false
		colors.append(mat.albedo_color)
		var top := cfg.tile_height
		if ov.position.y <= top or ov.position.y > top + 0.02:
			push_error("GridBoardView: overlay %s y=%.3f not just above grass top %.3f" % [cell, ov.position.y, top])
			return false
	if colors[0].is_equal_approx(colors[1]) or colors[1].is_equal_approx(colors[2]) or colors[0].is_equal_approx(colors[2]):
		push_error("GridBoardView: selected/move/attack overlays should differ in color")
		return false
	if (view._overlay_nodes[plain] as MeshInstance3D).visible:
		push_error("GridBoardView: un-highlighted overlay should stay hidden")
		return false
	var tile_mat := (view._tile_nodes[move] as MeshInstance3D).get_surface_override_material(0)
	var plain_mat := (view._tile_nodes[plain] as MeshInstance3D).get_surface_override_material(0)
	if tile_mat != plain_mat:
		push_error("GridBoardView: highlight must not swap shared terrain material")
		return false
	view.sync_tactical_units([], Vector2i(-1, -1), [], [])
	for cell in [sel, move, atk]:
		if (view._overlay_nodes[cell] as MeshInstance3D).visible:
			push_error("GridBoardView: overlay %s should hide after clear" % cell)
			return false
	return true


func _test_terrain_meshes_and_orientation() -> bool:
	var catalog := TerrainCatalog.load_default()
	var grass_def := catalog.get_def(&"grass")
	var wall_def := catalog.get_def(&"wall_straight")
	if grass_def == null or wall_def == null or grass_def.mesh == null or wall_def.mesh == null:
		push_error("GridBoardView: terrain defs/meshes missing in catalog")
		return false
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 5
	cfg.grid_height = 5
	var host := Control.new()
	host.size = Vector2(480, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	var cells := {
		Vector2i(1, 0): &"wall_straight",
		Vector2i(1, 1): &"wall_straight",
		Vector2i(1, 2): &"wall_straight",
		Vector2i(2, 4): &"wall_straight",
		Vector2i(3, 4): &"wall_straight",
		Vector2i(4, 4): &"wall_straight",
	}
	view.set_terrain_cells(cells)
	var wall_mi: MeshInstance3D = view._tile_nodes[Vector2i(1, 1)] as MeshInstance3D
	var grass_mi: MeshInstance3D = view._tile_nodes[Vector2i(3, 1)] as MeshInstance3D
	if wall_mi.mesh != wall_def.mesh:
		push_error("GridBoardView: wall cell mesh should be wall_straight def mesh")
		return false
	if grass_mi.mesh != grass_def.mesh:
		push_error("GridBoardView: grass cell mesh should be grass def mesh")
		return false
	if wall_mi.get_surface_override_material(1) != wall_def.surface_materials[1]:
		push_error("GridBoardView: wall stone surface should use shared def material")
		return false
	if not is_equal_approx(wall_mi.rotation.y, PI * 0.5):
		push_error("GridBoardView: vertical wall run should rotate 90° (got %.3f)" % wall_mi.rotation.y)
		return false
	var h_mi: MeshInstance3D = view._tile_nodes[Vector2i(3, 4)] as MeshInstance3D
	if absf(h_mi.rotation.y) > 0.001:
		push_error("GridBoardView: horizontal wall run should keep rotation 0 (got %.3f)" % h_mi.rotation.y)
		return false
	if view.terrain_id_at(Vector2i(0, 0)) != catalog.default_id:
		push_error("GridBoardView: unpainted cell should resolve to default terrain")
		return false
	view.set_terrain_cell(Vector2i(0, 1), &"wall_straight")
	if absf(wall_mi.rotation.y) > 0.001:
		push_error("GridBoardView: neighbor refresh should re-orient wall once it has an E/W neighbor")
		return false
	if StringName(view._terrain_cells.get(Vector2i(0, 1), &"")) != &"wall_straight":
		push_error("GridBoardView: _terrain_cells should store StringName ids")
		return false
	view.clear_terrain_paint()
	if wall_mi.mesh != grass_def.mesh:
		push_error("GridBoardView: clear_terrain_paint should restore default grass")
		return false
	return true


func _test_terrain_mesh_dimensions() -> bool:
	var cfg := load("res://resources/map/board_config.tres") as BoardConfig
	var catalog := TerrainCatalog.load_default()
	var wall_mesh := catalog.get_def(&"wall_straight").mesh
	var grass_mesh := catalog.get_def(&"grass").mesh
	var cs := cfg.cell_size
	var wall_aabb := wall_mesh.get_aabb()
	var expect_h := cfg.tile_height + 0.6 * cs
	if absf(wall_aabb.size.y - expect_h) > 0.02:
		push_error("GridBoardView: wall mesh height %.3f != %.3f" % [wall_aabb.size.y, expect_h])
		return false
	if absf(wall_aabb.size.x - cs) > 0.02:
		push_error("GridBoardView: wall mesh length %.3f != cell_size %.3f" % [wall_aabb.size.x, cs])
		return false
	if wall_mesh.get_surface_count() != 2 or grass_mesh.get_surface_count() != 1:
		push_error("GridBoardView: expected wall=2 surfaces (grass, stone), grass=1")
		return false
	var stone_aabb := _surface_aabb(wall_mesh, 1)
	if stone_aabb.size.z < 0.12 * cs or stone_aabb.size.z > 0.2 * cs:
		push_error("GridBoardView: wall thickness %.3f outside 0.12–0.2 U" % stone_aabb.size.z)
		return false
	if absf(stone_aabb.position.y - cfg.tile_height * 0.5) > 0.005:
		push_error("GridBoardView: wall should start on grass top (y=%.3f)" % stone_aabb.position.y)
		return false
	var grass_aabb := grass_mesh.get_aabb()
	var expect_inset := cs * cfg.tile_inset
	if absf(grass_aabb.size.x - expect_inset) > 0.005 or absf(grass_aabb.size.z - expect_inset) > 0.005:
		push_error("GridBoardView: grass tile footprint %s != inset %.3f" % [grass_aabb.size, expect_inset])
		return false
	return true


func _surface_aabb(mesh: Mesh, surface: int) -> AABB:
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box


func _test_grass_billboard_props() -> bool:
	var catalog := GrassPropCatalog.load_default()
	if catalog.prop_textures.is_empty():
		push_error("GridBoardView: grass prop catalog textures missing")
		return false
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 6
	cfg.grid_height = 6
	var host := Control.new()
	host.size = Vector2(480, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	var grass_cell := Vector2i(2, 2)
	var wall_cell := Vector2i(1, 1)
	view.set_terrain_cells({wall_cell: &"wall_straight"})
	var grass_host: Node3D = view._grass_prop_hosts[grass_cell] as Node3D
	var wall_host: Node3D = view._grass_prop_hosts[wall_cell] as Node3D
	if grass_host == null or wall_host == null:
		push_error("GridBoardView: grass prop host nodes missing")
		return false
	var grass_count := grass_host.get_child_count()
	if grass_count < 0 or grass_count > 3:
		push_error("GridBoardView: grass cell prop count %d out of 0..3" % grass_count)
		return false
	if wall_host.get_child_count() != 0:
		push_error("GridBoardView: wall cell should have no grass billboards")
		return false
	for child in grass_host.get_children():
		if not child is Sprite3D:
			push_error("GridBoardView: grass prop should be Sprite3D")
			return false
		var spr := child as Sprite3D
		if spr.billboard != BaseMaterial3D.BILLBOARD_ENABLED:
			push_error("GridBoardView: grass prop should face camera like units (BILLBOARD_ENABLED)")
			return false
		var tex_h := float(spr.texture.get_height())
		var world_h := spr.pixel_size * tex_h
		var feet_y := spr.position.y - world_h * 0.5
		var expect_feet := cfg.tile_height + GrassTileDecor.GRASS_PROP_FEET_LIFT
		if absf(feet_y - expect_feet) > 0.002:
			push_error(
				"GridBoardView: grass prop feet y %.4f != slab top %.4f"
				% [feet_y, expect_feet]
			)
			return false
	view.set_terrain_cell(grass_cell, &"grass")
	var grass_count_again := grass_host.get_child_count()
	if grass_count_again != grass_count:
		push_error("GridBoardView: grass props should be stable for the same cell seed")
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
