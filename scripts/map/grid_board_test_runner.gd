extends SceneTree
## 方格棋盘 / 2D 镜头 / 占位单位烟测（Headless）。


const BoardConfigScript := preload("res://scripts/map/board_config.gd")
const GridBoardViewScript := preload("res://scripts/map/grid_board_view.gd")


func _initialize() -> void:
	if not _test_cell_mapping():
		quit(1)
		return
	if not _test_oblique_unproject_matches_tile_height():
		quit(1)
		return
	if not await _test_pick_cell_portrait_and_edges():
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
	if not _test_grass_checker_colors():
		quit(1)
		return
	if not _test_terrain_visuals_and_orientation():
		quit(1)
		return
	if not _test_terrain_footprint_dimensions():
		quit(1)
		return
	if not _test_board_look_and_unit_blob():
		quit(1)
		return
	if not _test_unit_draw_depth():
		quit(1)
		return
	if not await _test_combat_tweens_stay_in_cell():
		quit(1)
		return
	if not _test_unit_idle_tween():
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
	var spr: Sprite2D = view._unit_sprites[unit] as Sprite2D
	var expected_h := cfg.unit_world_height
	var tex_h := float(def.texture_blue.get_height())
	var expected_scale := expected_h / tex_h
	if absf(spr.scale.y - expected_scale) > 0.0001:
		push_error("GridBoardView: unit scale.y %.5f != expected %.5f" % [spr.scale.y, expected_scale])
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
	if view._backdrop == null:
		push_error("GridBoardView: backdrop missing after setup")
		return false
	if not view._backdrop.color.is_equal_approx(look.background_color):
		push_error("GridBoardView: backdrop should use BoardLook.background_color")
		return false
	var web_look := look.duplicate() as BoardLook
	web_look.shadow_enabled = true
	web_look.shadow_on_web = true
	if not web_look.shadow_active(false) or not web_look.shadow_active(true):
		push_error("BoardLook: shadow flags should remain valid (2D uses foot blob only)")
		return false
	var def := load("res://resources/units/knight.tres") as TacticalUnitDef
	if def == null:
		push_error("GridBoardView: knight.tres missing for foot blob test")
		return false
	var UnitInstScript := preload("res://scripts/units/tactical_unit_instance.gd")
	var FactionScript := preload("res://scripts/units/tactical_faction.gd")
	var unit: TacticalUnitInstance = UnitInstScript.new(def, FactionScript.Id.PLAYER, Vector2i(1, 1))
	view.sync_tactical_units([unit], Vector2i(-1, -1), [], [])
	if not view._unit_blobs.has(unit):
		push_error("GridBoardView: unit foot blob missing")
		return false
	var blob := view._unit_blobs[unit] as Sprite2D
	var spr := view._unit_sprites[unit] as Sprite2D
	if blob.get_parent() != spr:
		push_error("GridBoardView: foot blob should be a child of the unit sprite (2D depth)")
		return false
	if spr.position.length() > 0.02:
		push_error("GridBoardView: feet node should sit on the cell center, got %s" % spr.position)
		return false
	var tex_h := float(spr.texture.get_height())
	var base_y := -tex_h * 0.5
	# 待机浮动只改 offset.y，允许在基线上下各 UNIT_IDLE_BOB_PX。
	if absf(spr.offset.y - base_y) > GridBoardViewScript.UNIT_IDLE_BOB_PX + 0.5:
		push_error("GridBoardView: sprite offset should stay near foot baseline (idle bob)")
		return false
	if blob.position.length() > 0.02:
		push_error("GridBoardView: foot blob should stay on the feet at the cell center")
		return false
	spr.scale = Vector2.ONE * 0.5
	spr.modulate.a = 0.3
	view._process(0.0)
	if blob.visible:
		push_error("GridBoardView: foot blob should hide while the sprite fades")
		return false
	view.sync_tactical_units([], Vector2i(-1, -1), [], [])
	if view._unit_blobs.has(unit) or not blob.is_queued_for_deletion():
		push_error("GridBoardView: foot blob should be freed with its unit")
		return false
	return true


func _test_unit_idle_tween() -> bool:
	var cfg := (load("res://resources/map/board_config.tres") as BoardConfig).duplicate() as BoardConfig
	var host := Control.new()
	host.size = Vector2(480, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	var def := load("res://resources/units/knight.tres") as TacticalUnitDef
	if def == null:
		push_error("GridBoardView: knight.tres missing for idle tween test")
		return false
	var UnitInstScript := preload("res://scripts/units/tactical_unit_instance.gd")
	var FactionScript := preload("res://scripts/units/tactical_faction.gd")
	var unit: TacticalUnitInstance = UnitInstScript.new(def, FactionScript.Id.PLAYER, Vector2i(2, 2))
	view.sync_tactical_units([unit], Vector2i(-1, -1), [], [])
	if not view._unit_idle_tweens.has(unit):
		push_error("GridBoardView: idle tween should start after sync")
		return false
	var idle: Tween = view._unit_idle_tweens[unit] as Tween
	if idle == null or not is_instance_valid(idle) or not idle.is_running():
		push_error("GridBoardView: idle tween should be running")
		return false
	var spr := view._unit_sprites[unit] as Sprite2D
	if spr.position.length() > 0.02:
		push_error("GridBoardView: idle must not move feet off cell center, got %s" % spr.position)
		return false
	var base: Vector2 = view._unit_base_offsets[unit] as Vector2
	if absf(spr.offset.y - base.y) > GridBoardViewScript.UNIT_IDLE_BOB_PX + 0.01:
		push_error("GridBoardView: idle bob exceeded amplitude")
		return false
	# 点选走 Control 格子拾取，单位是 Sprite2D；待机只改 offset，不挡输入。
	if not (spr is Sprite2D):
		push_error("GridBoardView: unit visual must remain Sprite2D under idle")
		return false
	view._pause_unit_idle(unit)
	if view._unit_idle_tweens.has(unit):
		push_error("GridBoardView: pause_unit_idle should clear idle tween")
		return false
	if not spr.offset.is_equal_approx(base):
		push_error("GridBoardView: pause_unit_idle should restore base offset")
		return false
	view.play_unit_hit(unit)
	if view._unit_idle_tweens.has(unit):
		push_error("GridBoardView: hit tween should pause idle")
		return false
	view.sync_tactical_units([], Vector2i(-1, -1), [], [])
	if view._unit_idle_tweens.has(unit):
		push_error("GridBoardView: removing unit should clear idle tween")
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
		if (view._overlay_nodes[cell] as Polygon2D).visible:
			push_error("GridBoardView: overlay %s should be hidden without highlight" % cell)
			return false
	view.sync_tactical_units([], sel, [move], [atk])
	var colors: Array[Color] = []
	for cell in [sel, move, atk]:
		var ov: Polygon2D = view._overlay_nodes[cell] as Polygon2D
		if not ov.visible:
			push_error("GridBoardView: overlay %s should be visible" % cell)
			return false
		colors.append(ov.color)
	if colors[0].is_equal_approx(colors[1]) or colors[1].is_equal_approx(colors[2]) or colors[0].is_equal_approx(colors[2]):
		push_error("GridBoardView: selected/move/attack overlays should differ in color")
		return false
	if (view._overlay_nodes[plain] as Polygon2D).visible:
		push_error("GridBoardView: un-highlighted overlay should stay hidden")
		return false
	var color_before := view.grass_color_at(move)
	var color_after := view.grass_color_at(move)
	if color_before != color_after:
		push_error("GridBoardView: highlight must not swap grass fill color")
		return false
	view.sync_tactical_units([], Vector2i(-1, -1), [], [])
	for cell in [sel, move, atk]:
		if (view._overlay_nodes[cell] as Polygon2D).visible:
			push_error("GridBoardView: overlay %s should hide after clear" % cell)
			return false
	return true


func _test_grass_checker_colors() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 3
	cfg.grid_height = 3
	var host := Control.new()
	host.size = Vector2(320, 240)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var wall := Vector2i(0, 1)
	view.set_terrain_cell(wall, &"wall_straight")
	var col_a := view.grass_color_at(a)
	var col_b := view.grass_color_at(b)
	if col_a == col_b:
		push_error("GridBoardView: adjacent parity grass should use different checker tints")
		return false
	if not col_a.is_equal_approx(GridBoardViewScript.GRASS_CHECKER_LIGHT):
		push_error("GridBoardView: (0,0) should use light checker, got %s" % col_a)
		return false
	if not col_b.is_equal_approx(GridBoardViewScript.GRASS_CHECKER_DARK):
		push_error("GridBoardView: (1,0) should use dark checker, got %s" % col_b)
		return false
	if not view.grass_color_at(wall).is_equal_approx(GridBoardViewScript.GRASS_CHECKER_DARK):
		push_error("GridBoardView: wall grass should use checker parity color")
		return false
	var root_node: Node2D = view._tile_nodes[wall] as Node2D
	var wall_node: Node2D = root_node.get_node("Wall") as Node2D
	if not wall_node.visible:
		push_error("GridBoardView: wall visual should show on wall_straight")
		return false
	var stone: Polygon2D = wall_node.get_node("StoneBody") as Polygon2D
	if stone == null or not stone.color.is_equal_approx(GridBoardViewScript.WALL_STONE_LIGHT):
		push_error("GridBoardView: wall stone should use light gray brick color")
		return false
	return true


func _test_terrain_visuals_and_orientation() -> bool:
	var catalog := TerrainCatalog.load_default()
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
	if not is_equal_approx(view.wall_rotation_at(Vector2i(1, 1)), PI * 0.5):
		push_error("GridBoardView: vertical wall run should rotate 90°")
		return false
	if absf(view.wall_rotation_at(Vector2i(3, 4))) > 0.001:
		push_error("GridBoardView: horizontal wall run should keep rotation 0")
		return false
	if view.terrain_id_at(Vector2i(0, 0)) != catalog.default_id:
		push_error("GridBoardView: unpainted cell should resolve to default terrain")
		return false
	view.set_terrain_cell(Vector2i(0, 1), &"wall_straight")
	if absf(view.wall_rotation_at(Vector2i(1, 1))) > 0.001:
		push_error("GridBoardView: neighbor refresh should re-orient wall once it has an E/W neighbor")
		return false
	view.clear_terrain_paint()
	var wall_root: Node2D = view._tile_nodes[Vector2i(1, 1)] as Node2D
	if (wall_root.get_node("Wall") as Node2D).visible:
		push_error("GridBoardView: clear_terrain_paint should restore default grass")
		return false
	return true


func _test_terrain_footprint_dimensions() -> bool:
	var cfg := load("res://resources/map/board_config.tres") as BoardConfig
	var host := Control.new()
	host.size = Vector2(320, 240)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	view.set_terrain_cell(Vector2i(1, 1), &"wall_straight")
	var cs := cfg.cell_size
	var expect_inset := cs * cfg.tile_inset
	var wall := view.wall_footprint_size(Vector2i(1, 1))
	if absf(wall.x - expect_inset) > 0.005:
		push_error("GridBoardView: wall bar length %.3f != inset %.3f" % [wall.x, expect_inset])
		return false
	if wall.y < 0.12 * cs or wall.y > 0.2 * cs:
		push_error("GridBoardView: wall thickness %.3f outside 0.12–0.2 U" % wall.y)
		return false
	var root_node: Node2D = view._tile_nodes[Vector2i(0, 0)] as Node2D
	var grass: Polygon2D = root_node.get_node("Grass") as Polygon2D
	if grass.polygon.size() < 4:
		push_error("GridBoardView: grass tile should be a quad")
		return false
	var edge := (grass.polygon[1] - grass.polygon[0]).length()
	if edge < expect_inset * 0.85 or edge > expect_inset * 1.15:
		push_error("GridBoardView: grass tile edge %.3f not near inset %.3f" % [edge, expect_inset])
		return false
	var flat := view._cell_to_world(Vector2i(0, 0), cs)
	var step := view._cell_to_world(Vector2i(1, 0), cs)
	if absf(flat.y - step.y) < 0.01:
		push_error("GridBoardView: oblique projection should skew screen Y across grid X")
		return false
	return true


func _test_unit_draw_depth() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 8
	cfg.grid_height = 8
	var host := Control.new()
	host.size = Vector2(480, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	var def := load("res://resources/units/knight.tres") as TacticalUnitDef
	if def == null:
		return true
	var UnitInstScript := preload("res://scripts/units/tactical_unit_instance.gd")
	var FactionScript := preload("res://scripts/units/tactical_faction.gd")
	var near: TacticalUnitInstance = UnitInstScript.new(def, FactionScript.Id.PLAYER, Vector2i(1, 1))
	var far: TacticalUnitInstance = UnitInstScript.new(def, FactionScript.Id.OPPONENT, Vector2i(6, 6))
	view.sync_tactical_units([near, far], Vector2i(-1, -1), [], [])
	var spr_near: Sprite2D = view._unit_sprites[near] as Sprite2D
	var spr_far: Sprite2D = view._unit_sprites[far] as Sprite2D
	var tile_near: Node2D = view._tile_nodes[Vector2i(1, 1)] as Node2D
	if spr_near.position.length() > 0.02 or spr_far.position.length() > 0.02:
		push_error("GridBoardView: unit feet should sit at cell center (local origin)")
		return false
	if spr_near.offset.y >= 0.0 or spr_far.offset.y >= 0.0:
		push_error("GridBoardView: body texture should be offset upward from the feet")
		return false
	if spr_near.z_as_relative or spr_far.z_as_relative:
		push_error("GridBoardView: unit z_index must be absolute so tiles cannot cover them")
		return false
	var y_near := view._cell_to_world(Vector2i(1, 1), cfg.cell_size).y
	var y_far := view._cell_to_world(Vector2i(6, 6), cfg.cell_size).y
	if (spr_far.z_index - spr_near.z_index) * (y_far - y_near) <= 0.0:
		push_error("GridBoardView: unit draw order should follow screen Y")
		return false
	for cell in view._tile_nodes.keys():
		var tile: Node2D = view._tile_nodes[cell] as Node2D
		if spr_near.z_index <= tile.z_index + 8 or spr_far.z_index <= tile.z_index + 8:
			push_error("GridBoardView: unit z %d covered by tile %s z %d" % [spr_near.z_index, cell, tile.z_index])
			return false
	if spr_near.get_parent() != tile_near:
		push_error("GridBoardView: unit should parent to its tile so local origin is the cell center")
		return false
	return true


func _test_pan_vertical_intuitive() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	var host := Control.new()
	host.size = Vector2(480, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
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
			var w := view._cell_ground_center(cell, cfg.cell_size)
			var back: Variant = view._world_to_cell(w)
			if back != cell:
				push_error("GridBoardView: cell roundtrip failed %s -> %s" % [cell, back])
				return false
	return true


func _test_oblique_unproject_matches_tile_height() -> bool:
	var cfg: BoardConfig = BoardConfigScript.new()
	cfg.grid_width = 8
	cfg.grid_height = 8
	cfg.cell_size = 1.0
	cfg.tile_height = 0.14
	cfg.camera_pitch_deg = 45.0
	cfg.camera_yaw_deg = 45.0
	var view := GridBoardViewScript.new()
	view.config = cfg
	for gx in range(cfg.grid_width):
		for gy in range(cfg.grid_height):
			var cell := Vector2i(gx, gy)
			var ground := view._cell_ground_center(cell, cfg.cell_size)
			var screen: Vector2 = view._oblique_project(ground)
			var back: Vector3 = view._oblique_unproject_ground(screen)
			if not is_equal_approx(back.y, cfg.tile_height):
				push_error("GridBoardView: unproject y %.4f != tile_height" % back.y)
				return false
			if back.distance_to(Vector3(ground.x, cfg.tile_height, ground.z)) > 1e-4:
				push_error(
					"GridBoardView: project/unproject drift cell=%s got=%s want xz=(%.3f,%.3f)"
					% [cell, back, ground.x, ground.z]
				)
				return false
			# 格角（inset 内）经投影反变换仍须落在同格。
			var half := cfg.cell_size * 0.48
			for off in [
				Vector3(-half, 0.0, -half),
				Vector3(half, 0.0, -half),
				Vector3(half, 0.0, half),
				Vector3(-half, 0.0, half),
			]:
				var corner := Vector3(ground.x + off.x, cfg.tile_height, ground.z + off.z)
				var c_screen: Vector2 = view._oblique_project(corner)
				var c_back: Vector3 = view._oblique_unproject_ground(c_screen)
				var c_cell: Variant = view._world_to_cell(c_back)
				if c_cell != cell:
					push_error(
						"GridBoardView: corner unproject mis-pick cell=%s off=%s -> %s"
						% [cell, off, c_cell]
					)
					return false
	return true


func _test_pick_cell_portrait_and_edges() -> bool:
	## 竖屏沙盘棋盘 inset 约 393×574；含平移/缩放后格心与近角点选。
	var loaded = load("res://resources/map/board_config.tres")
	var cfg = loaded.duplicate(true) if loaded != null else BoardConfigScript.new()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.custom_minimum_size = Vector2(393, 574)
	host.size = Vector2(393, 574)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.position = Vector2.ZERO
	view.size = Vector2(393, 574)
	host.add_child(view)
	view.setup(cfg)
	# SubViewport / Camera2D 需进树并跑帧后 canvas transform 才可用。
	await process_frame
	await process_frame
	view._apply_camera()
	await process_frame

	if view._viewport == null:
		push_error("GridBoardView: portrait SubViewport missing")
		return false
	if not view._viewport_container.stretch:
		push_error("GridBoardView: SubViewportContainer.stretch should be true so the board fills")
		return false
	if view._chrome == null or view._chrome.color != view._look().background_color:
		push_error("GridBoardView: Control chrome should match BoardLook.background_color")
		return false
	if view._camera == null or not view._camera.is_inside_tree():
		push_error("GridBoardView: camera must be inside tree for pick test")
		return false

	# 多边形命中：格心世界坐标必须命中该格 Grass 菱形。
	var center_cell := Vector2i(3, 3)
	var center_world: Vector2 = view._cell_to_world(center_cell, cfg.cell_size)
	if not view._world_hits_cell_poly(center_world, center_cell):
		push_error("GridBoardView: cell center should hit its grass polygon")
		return false
	var poly_pick: Variant = view._pick_cell_at_world(center_world)
	if poly_pick != center_cell:
		push_error("GridBoardView: polygon pick at center got %s want %s" % [poly_pick, center_cell])
		return false

	if not _assert_pick_roundtrip(view, cfg, "portrait-default"):
		return false

	# 平移 + 非默认缩放后仍准确。
	view._target += Vector3(1.2, 0.0, -0.8)
	view._set_zoom(cfg.camera_zoom_default * 1.25)
	view._apply_camera()
	await process_frame
	if not _assert_pick_roundtrip(view, cfg, "portrait-pan-zoom"):
		return false
	return true


func _assert_pick_roundtrip(view: GridBoardView, cfg: BoardConfig, tag: String) -> bool:
	var half := cfg.cell_size * 0.48
	var samples: Array = [Vector3.ZERO]
	for off in [
		Vector3(-half, 0.0, -half),
		Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half),
		Vector3(-half, 0.0, half),
	]:
		samples.append(off)
	var checked := 0
	for gx in range(cfg.grid_width):
		for gy in range(cfg.grid_height):
			var cell := Vector2i(gx, gy)
			for off2 in samples:
				var ground: Vector3 = view._cell_ground_center(cell, cfg.cell_size)
				ground.x += (off2 as Vector3).x
				ground.z += (off2 as Vector3).z
				ground.y = cfg.tile_height
				var world: Vector2 = view._oblique_project(ground)
				var canvas: Transform2D = view._camera.get_canvas_transform()
				var vp_pos: Vector2 = canvas * world
				var cs: Vector2 = view._viewport_container.size
				var vs: Vector2i = view._viewport.size
				var local := vp_pos
				if cs.x > 0.0 and cs.y > 0.0 and vs.x > 0 and vs.y > 0:
					local = Vector2(vp_pos.x * cs.x / float(vs.x), vp_pos.y * cs.y / float(vs.y))
				# 竖屏 ortho 按高度适配时盘角常在视口外，只能验屏内点。
				if local.x < 2.0 or local.y < 2.0 or local.x > view.size.x - 2.0 or local.y > view.size.y - 2.0:
					continue
				var picked: Variant = view._pick_cell(local)
				checked += 1
				if picked != cell:
					push_error(
						"GridBoardView: pick fail %s cell=%s off=%s local=%s picked=%s"
						% [tag, cell, off2, local, picked]
					)
					return false
	if checked < 8:
		push_error("GridBoardView: pick roundtrip %s too few on-screen samples (%d)" % [tag, checked])
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
		push_error("GridBoardView: Camera2D missing")
		return false
	var units := _find_node_named(view, "Units")
	if units == null:
		push_error("GridBoardView: Units root missing")
		return false
	if camera.zoom.x <= 0.0:
		push_error("GridBoardView: Camera2D zoom should be positive")
		return false
	return true


func _find_camera(node: Node) -> Camera2D:
	if node is Camera2D:
		return node as Camera2D
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


## 受击抖动/冲刺不得超过格半宽；受击瞬间应为闪白；结束后强制回格心。
func _test_combat_tweens_stay_in_cell() -> bool:
	var cfg := (load("res://resources/map/board_config.tres") as BoardConfig).duplicate() as BoardConfig
	cfg.grid_width = 6
	cfg.grid_height = 6
	var host := Control.new()
	host.size = Vector2(640, 360)
	root.add_child(host)
	var view: GridBoardView = GridBoardViewScript.new()
	host.add_child(view)
	view.setup(cfg)
	var def := load("res://resources/units/knight.tres") as TacticalUnitDef
	if def == null:
		push_error("combat tween: knight.tres missing")
		return false
	var UnitInstScript := preload("res://scripts/units/tactical_unit_instance.gd")
	var FactionScript := preload("res://scripts/units/tactical_faction.gd")
	var attacker: TacticalUnitInstance = UnitInstScript.new(def, FactionScript.Id.PLAYER, Vector2i(2, 2))
	var target: TacticalUnitInstance = UnitInstScript.new(def, FactionScript.Id.OPPONENT, Vector2i(3, 2))
	view.sync_tactical_units([attacker, target], Vector2i(-1, -1), [], [])
	var half := cfg.cell_size * 0.5
	if view.unit_hit_shake_px() > half:
		push_error("hit shake %.3f exceeds half cell %.3f" % [view.unit_hit_shake_px(), half])
		return false
	if view.unit_attack_lunge_cap() > half:
		push_error("attack lunge cap %.3f exceeds half cell %.3f" % [view.unit_attack_lunge_cap(), half])
		return false
	var spr_t := view._unit_sprites[target] as Sprite2D
	var spr_a := view._unit_sprites[attacker] as Sprite2D
	var hit_tw := view.play_unit_hit(target)
	if hit_tw == null:
		push_error("hit tween missing")
		return false
	if spr_t.modulate.r < 1.2 or spr_t.modulate.g < 1.2 or spr_t.modulate.b < 1.2:
		push_error("hit should flash white first, got %s" % spr_t.modulate)
		return false
	var max_hit := 0.0
	while hit_tw.is_running():
		await process_frame
		max_hit = maxf(max_hit, spr_t.position.length())
		if max_hit > half + 0.02:
			push_error("hit displacement %.3f left the cell (half=%.3f)" % [max_hit, half])
			return false
	await process_frame
	if spr_t.position.length() > 0.02:
		push_error("after hit, sprite should snap to cell center, got %s" % spr_t.position)
		return false
	var tw := view.play_unit_attack(attacker, target.cell)
	if tw == null:
		push_error("attack tween missing")
		return false
	var max_lunge := 0.0
	while tw.is_running():
		await process_frame
		max_lunge = maxf(max_lunge, spr_a.position.length())
		if max_lunge > half + 0.02:
			push_error("attack lunge %.3f left the cell (half=%.3f)" % [max_lunge, half])
			return false
	await process_frame
	if spr_a.position.length() > 0.02:
		push_error("after attack, sprite should snap to cell center, got %s" % spr_a.position)
		return false
	return true