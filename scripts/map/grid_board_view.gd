class_name GridBoardView
extends Control
## 2D 方格盘（斜 45° 正交投影）：Polygon2D 格块 + Sprite2D 单位；Camera2D 拖拽/滚轮。


signal cell_clicked(cell: Vector2i)

var config: BoardConfig

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _backdrop: ColorRect
var _world_root: Node2D
var _tiles_root: Node2D
var _units_root: Node2D
var _labels_layer: CanvasLayer
var _labels_root: Control
var _camera: Camera2D
var _pivot: Node2D
var _tile_nodes: Dictionary = {} # Vector2i -> Node2D (Tile root)
var _overlay_nodes: Dictionary = {} # Vector2i -> Polygon2D
var _catalog: TerrainCatalog

var _target: Vector3 = Vector3.ZERO
var _zoom: float = 1.0
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _press_pos: Vector2 = Vector2.ZERO
var _needs_center: bool = true

const DRAG_THRESHOLD_PX := 6.0
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const OVERLAY_Z := 4
const WALL_Z := 2
const GRASS_Z := 0
## 按格深度排序：同 stride 下 overlay(4) < 单位(8)。
const DRAW_DEPTH_STRIDE := 16
const UNIT_DRAW_LAYER := 8
const UNIT_FEET_LIFT := 0.02
const OVERLAY_COLORS := {
	"s": Color(0.35, 0.56, 0.83, 0.5),
	"m": Color(0.42, 1.0, 0.72, 0.58),
	"a": Color(0.82, 0.28, 0.31, 0.5),
}
const GRASS_CHECKER_LIGHT := Color("B4A158")
const GRASS_CHECKER_DARK := Color("8F884C")
const WALL_STONE_LIGHT := Color("9c958c")
const WALL_STONE_DARK := Color("716c65")

var _terrain_cells: Dictionary = {} # Vector2i -> StringName

var _unit_sprites: Dictionary = {} # TacticalUnitInstance -> Sprite2D
var _overlay_selected: Vector2i = Vector2i(-1, -1)
var _overlay_move: Dictionary = {}
var _overlay_attack: Dictionary = {}

var _last_unit_cells: Dictionary = {}
var _hp_bars: Dictionary = {} # TacticalUnitInstance -> Label
var _unit_blobs: Dictionary = {} # TacticalUnitInstance -> Sprite2D
var _blob_texture: Texture2D

var _touch_drag_index: int = -1
var _active_touches: Dictionary = {}
var _pinch_last_distance: float = 0.0


func setup(p_config: BoardConfig) -> void:
	config = p_config
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_viewport_tree()
	_apply_look()
	_zoom = clampf(config.camera_zoom_default, config.camera_zoom_min, config.camera_zoom_max)
	_needs_center = true
	_rebuild_board()
	_try_center_on_board()
	_apply_camera()


func set_terrain_catalog(catalog: TerrainCatalog) -> void:
	_catalog = catalog
	for cell in _tile_nodes.keys():
		_apply_tile_visual(cell)


func clear_terrain_paint() -> void:
	_terrain_cells.clear()
	for cell in _tile_nodes.keys():
		_apply_tile_visual(cell)


func set_terrain_cells(cells: Dictionary) -> void:
	_terrain_cells.clear()
	for key in cells.keys():
		if key is Vector2i:
			_terrain_cells[key] = _normalize_terrain_id(cells[key])
	for cell in _tile_nodes.keys():
		_apply_tile_visual(cell)


func set_terrain_cell(cell: Vector2i, terrain_id: StringName) -> void:
	if not _tile_nodes.has(cell):
		return
	_terrain_cells[cell] = _normalize_terrain_id(terrain_id)
	_apply_tile_visual(cell)
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		_apply_tile_visual(cell + (d as Vector2i))


func terrain_id_at(cell: Vector2i) -> StringName:
	var cat := _get_catalog()
	return cat.resolve_id(StringName(_terrain_cells.get(cell, cat.default_id)))


func _get_catalog() -> TerrainCatalog:
	if _catalog == null:
		_catalog = TerrainCatalog.load_default()
	return _catalog


func _normalize_terrain_id(value: Variant) -> StringName:
	var cat := _get_catalog()
	if value is int:
		push_warning("GridBoardView: legacy int terrain code %d; pass TerrainTypeDef.id" % int(value))
		return cat.from_legacy_code(int(value))
	return cat.resolve_id(StringName(str(value)))


func _ready() -> void:
	_ensure_viewport_tree()
	resized.connect(_on_resized)
	_on_resized()


func _ensure_viewport_tree() -> void:
	if _viewport_container != null:
		return
	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport_container.add_child(_viewport)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_backdrop)

	_world_root = Node2D.new()
	_world_root.name = "BoardWorld"
	_viewport.add_child(_world_root)

	_pivot = Node2D.new()
	_pivot.name = "CameraPivot"
	_world_root.add_child(_pivot)

	_camera = Camera2D.new()
	_camera.name = "BoardCamera"
	_camera.enabled = true
	_pivot.add_child(_camera)

	_tiles_root = Node2D.new()
	_tiles_root.name = "Tiles"
	_world_root.add_child(_tiles_root)

	_units_root = Node2D.new()
	_units_root.name = "Units"
	_world_root.add_child(_units_root)

	_labels_layer = CanvasLayer.new()
	_labels_layer.name = "BoardLabels"
	_viewport.add_child(_labels_layer)

	_labels_root = Control.new()
	_labels_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_labels_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels_layer.add_child(_labels_root)


func _look() -> BoardLook:
	if config != null and config.look != null:
		return config.look
	return BoardLook.new()


func _apply_look() -> void:
	if _backdrop != null:
		_backdrop.color = _look().background_color
	_blob_texture = null


func _on_resized() -> void:
	if config == null:
		return
	if _viewport != null and _viewport_container != null:
		var sz := _viewport_container.size
		if sz.x > 1.0 and sz.y > 1.0:
			_viewport.size = Vector2i(sz)
	if _needs_center:
		_try_center_on_board()
	_apply_camera()


func _try_center_on_board() -> void:
	if size.x <= 1.0 or size.y <= 1.0 or config == null:
		return
	_target = _cell_ground_center(Vector2i(config.grid_width / 2, config.grid_height / 2), config.cell_size)
	_target.y = 0.0
	_needs_center = false
	_clamp_target()
	_apply_camera()


func _rebuild_board() -> void:
	if config == null or _tiles_root == null:
		return
	for child in _tiles_root.get_children():
		child.queue_free()
	for child in _units_root.get_children():
		child.queue_free()
	_tile_nodes.clear()
	_overlay_nodes.clear()
	_unit_sprites.clear()
	_unit_blobs.clear()
	_hp_bars.clear()
	_last_unit_cells.clear()

	var cell_size := config.cell_size
	for gx in range(config.grid_width):
		for gy in range(config.grid_height):
			var cell := Vector2i(gx, gy)
			var root := Node2D.new()
			root.name = "Tile_%d_%d" % [gx, gy]
			root.position = _cell_to_world(cell, cell_size)
			_tiles_root.add_child(root)
			_tile_nodes[cell] = root

			var grass := Polygon2D.new()
			grass.name = "Grass"
			grass.z_index = GRASS_Z
			root.add_child(grass)

			var wall := Node2D.new()
			wall.name = "Wall"
			wall.z_index = WALL_Z
			wall.visible = false
			root.add_child(wall)

			var ov := Polygon2D.new()
			ov.name = "Overlay"
			ov.z_index = OVERLAY_Z
			ov.visible = false
			root.add_child(ov)
			_overlay_nodes[cell] = ov

	for cell in _tile_nodes.keys():
		_update_tile_geometry(cell)
		_apply_tile_visual(cell)


func sync_tactical_units(
	units: Array,
	selected_cell: Vector2i,
	move_cells: Array,
	attack_cells: Array
) -> void:
	if config == null or _units_root == null:
		return
	_overlay_selected = selected_cell
	_overlay_move.clear()
	for c in move_cells:
		if c is Vector2i:
			_overlay_move[c] = true
	_overlay_attack.clear()
	for c in attack_cells:
		if c is Vector2i:
			_overlay_attack[c] = true
	var alive: Dictionary = {}
	for u in units:
		if u is TacticalUnitInstance and (u as TacticalUnitInstance).is_alive():
			alive[u] = true
			_ensure_unit_sprite(u as TacticalUnitInstance)
			_sync_unit_position(u as TacticalUnitInstance)
	for key in _unit_sprites.keys():
		if not alive.has(key):
			_remove_unit_visual(key)
	for cell in _overlay_nodes.keys():
		_apply_overlay(cell)


func _sync_unit_position(unit: TacticalUnitInstance) -> void:
	var spr := _unit_sprites[unit] as Sprite2D
	var local_pose := _unit_local_pose_on_tile(unit.cell)
	var world_pose := _unit_pose_screen(unit.cell)
	var prev: Variant = _last_unit_cells.get(unit, unit.cell)
	_last_unit_cells[unit] = unit.cell
	if prev is Vector2i and prev != unit.cell and is_inside_tree():
		_float_unit_for_world_tween(spr)
		_tween_unit_to(spr, world_pose["torso"], unit, local_pose)
	else:
		_mount_unit_on_tile(unit)
		spr.position = local_pose["torso"]
		_sync_unit_blob_pose(unit, local_pose)
	_update_hp_bar(unit)


const UNIT_MOVE_TWEEN_SEC := 0.26


func unit_move_duration_sec() -> float:
	return UNIT_MOVE_TWEEN_SEC


func _tween_unit_to(
	spr: Sprite2D,
	target_world: Vector2,
	unit: TacticalUnitInstance,
	target_local: Dictionary
) -> void:
	var tw := create_tween()
	tw.tween_property(spr, "position", target_world, UNIT_MOVE_TWEEN_SEC).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tw.finished.connect(func() -> void:
		_mount_unit_on_tile(unit)
		spr.position = target_local["torso"]
		_sync_unit_blob_pose(unit, target_local)
		_update_hp_bar(unit)
	)


func play_unit_attack(attacker: TacticalUnitInstance, target_cell: Vector2i) -> Tween:
	if config == null or not _unit_sprites.has(attacker):
		return null
	var spr := _unit_sprites[attacker] as Sprite2D
	var home := spr.position
	var world := _cell_to_world(target_cell, config.cell_size)
	var delta := _cell_to_world(target_cell, config.cell_size) - _cell_to_world(attacker.cell, config.cell_size)
	var flat := delta
	var lunge := home
	if flat.length_squared() > 0.0001:
		lunge = home + flat.normalized() * minf(flat.length() * 0.42, config.cell_size * 0.55)
	var tw := create_tween()
	tw.tween_property(spr, "position", lunge, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "position", home, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw


func attack_tween_duration_sec() -> float:
	return 0.28


func _remove_unit_visual(unit: TacticalUnitInstance) -> void:
	if _unit_sprites.has(unit):
		var spr: Sprite2D = _unit_sprites[unit] as Sprite2D
		spr.queue_free()
		_unit_sprites.erase(unit)
	if _unit_blobs.has(unit):
		(_unit_blobs[unit] as Node).queue_free()
		_unit_blobs.erase(unit)
	if _hp_bars.has(unit):
		var bar: Label = _hp_bars[unit] as Label
		bar.queue_free()
		_hp_bars.erase(unit)
	_last_unit_cells.erase(unit)


func play_damage_popup(cell: Vector2i, amount: int) -> void:
	if config == null:
		return
	var ground := _cell_ground_center(cell, config.cell_size)
	ground.y = config.tile_height + config.unit_world_height * 0.55
	var world := _oblique_project(ground)
	var lift := 0.0
	var lbl := Label.new()
	lbl.text = "-%d!" % amount
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.modulate = Color("ff6644")
	_labels_root.add_child(lbl)
	_position_world_on_label(lbl, world + Vector2(0.0, lift - 36.0))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(pos: Vector2): _position_world_on_label(lbl, pos), lbl.position, lbl.position + Vector2(0, -36), 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.45).set_delay(0.12)
	tw.finished.connect(lbl.queue_free)


func play_unit_hit(unit: TacticalUnitInstance) -> void:
	if not _unit_sprites.has(unit):
		return
	var spr := _unit_sprites[unit] as Sprite2D
	var base := spr.position
	spr.modulate = Color("ff8888")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "modulate", _look().unit_modulate, 0.32)
	tw.tween_property(spr, "position:x", base.x + 4.0, 0.06).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(spr, "position", base, 0.12).set_trans(Tween.TRANS_SINE)


func play_unit_death(unit: TacticalUnitInstance) -> void:
	if not _unit_sprites.has(unit):
		return
	var spr := _unit_sprites[unit] as Sprite2D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", Vector2(0.05, 0.05), 0.32)
	tw.tween_property(spr, "modulate:a", 0.0, 0.32)


func _ensure_unit_sprite(unit: TacticalUnitInstance) -> void:
	var spr: Sprite2D
	if _unit_sprites.has(unit):
		spr = _unit_sprites[unit] as Sprite2D
	else:
		spr = Sprite2D.new()
		spr.name = "Unit_%s_%s" % [unit.def.id, unit.faction]
		spr.centered = true
		spr.offset = Vector2.ZERO
		_unit_sprites[unit] = spr
		_attach_unit_blob(unit)
	var tex := unit.def.texture_blue
	if unit.faction == TacticalFactionScript.Id.OPPONENT:
		tex = unit.def.texture_red
	var unit_h: float = config.unit_world_height
	var tex_h := float(tex.get_height())
	if tex_h > 0.0:
		var s := unit_h / tex_h
		spr.scale = Vector2(s, s)
	spr.texture = tex
	spr.modulate = _look().unit_modulate if unit.is_alive() else Color(0.4, 0.4, 0.4, 0.5)
	spr.scale = Vector2(unit_h / tex_h, unit_h / tex_h) if tex_h > 0.0 else Vector2.ONE
	_ensure_hp_bar(unit)


func _attach_unit_blob(unit: TacticalUnitInstance) -> void:
	var spr := _unit_sprites.get(unit) as Sprite2D
	if spr == null:
		return
	var look := _look()
	if look.unit_blob_opacity <= 0.0:
		return
	if _blob_texture == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(0.08, 0.07, 0.04, look.unit_blob_opacity))
		grad.set_color(1, Color(0.08, 0.07, 0.04, 0.0))
		grad.add_point(0.55, Color(0.08, 0.07, 0.04, look.unit_blob_opacity * 0.85))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_blob_texture = tex
	var blob := Sprite2D.new()
	blob.name = "Blob"
	blob.texture = _blob_texture
	blob.centered = true
	blob.z_index = -1
	var r := look.unit_blob_radius * config.cell_size * 2.0
	blob.scale = Vector2(r / 64.0, r / 64.0 * 0.7)
	spr.add_child(blob)
	_unit_blobs[unit] = blob


const BLOB_HIDE_ALPHA := 0.6


func _process(_delta: float) -> void:
	for unit in _hp_bars:
		if _unit_sprites.has(unit):
			_update_hp_bar(unit as TacticalUnitInstance)
	for unit in _unit_blobs:
		var spr := _unit_sprites.get(unit) as Sprite2D
		if spr == null:
			continue
		var blob := _unit_blobs[unit] as Sprite2D
		var s := absf(spr.scale.x)
		var r := _look().unit_blob_radius * config.cell_size * 2.0
		blob.scale = Vector2(s * r / 64.0, s * r / 64.0 * 0.7)
		blob.visible = spr.modulate.a > BLOB_HIDE_ALPHA


func _ensure_hp_bar(unit: TacticalUnitInstance) -> void:
	var bar: Label
	if _hp_bars.has(unit):
		bar = _hp_bars[unit] as Label
	else:
		bar = Label.new()
		bar.add_theme_font_size_override("font_size", 12)
		bar.add_theme_color_override("font_outline_color", Color("0a1018"))
		bar.add_theme_constant_override("outline_size", 3)
		_labels_root.add_child(bar)
		_hp_bars[unit] = bar
	_update_hp_bar(unit)


func _update_hp_bar(unit: TacticalUnitInstance) -> void:
	if not _hp_bars.has(unit) or not _unit_sprites.has(unit):
		return
	var bar := _hp_bars[unit] as Label
	var spr := _unit_sprites[unit] as Sprite2D
	bar.text = "%d/%d" % [unit.hp, unit.def.max_hp]
	var local_pose := _unit_local_pose_on_tile(unit.cell)
	var head_off: Vector2 = local_pose["head"] - local_pose["torso"]
	_position_world_on_label(bar, _unit_world_position(spr) + head_off)
	if unit.hp <= unit.def.max_hp / 3:
		bar.modulate = Color("ff6666")
	else:
		bar.modulate = Color("e8f0ff")


func _position_world_on_label(lbl: Control, world: Vector2) -> void:
	if _camera == null or not _camera.is_inside_tree():
		lbl.position = world
		return
	var canvas := _camera.get_canvas_transform()
	var screen := canvas * world
	lbl.position = screen - lbl.size * 0.5


func _grass_color_for_cell(cell: Vector2i, terrain_id: StringName) -> Color:
	if not _uses_grass_checker_surface(terrain_id):
		var def := _get_catalog().get_def(terrain_id)
		return def.editor_color if def != null else Color("6f9a3c")
	var parity: int = (cell.x + cell.y) & 1
	return GRASS_CHECKER_DARK if parity == 1 else GRASS_CHECKER_LIGHT


func _uses_grass_checker_surface(terrain_id: StringName) -> bool:
	return terrain_id == _get_catalog().default_id or terrain_id == &"wall_straight"


func _apply_tile_visual(cell: Vector2i) -> void:
	if config == null or not _tile_nodes.has(cell):
		return
	var root: Node2D = _tile_nodes[cell] as Node2D
	var terrain_id := terrain_id_at(cell)
	var def := _get_catalog().get_def(terrain_id)
	var grass: Polygon2D = root.get_node_or_null("Grass") as Polygon2D
	if grass != null:
		grass.color = _grass_color_for_cell(cell, terrain_id)
	var wall: Node2D = root.get_node_or_null("Wall") as Node2D
	var is_wall := terrain_id == &"wall_straight"
	if wall != null:
		wall.visible = is_wall
		if is_wall:
			_update_wall_geometry(cell, _tile_yaw(cell, terrain_id, def))
	root.rotation = 0.0
	root.z_index = _draw_depth_for_cell(cell)
	_apply_overlay(cell)


func _tile_yaw(cell: Vector2i, terrain_id: StringName, def: TerrainTypeDef) -> float:
	if def != null and def.orient_to_neighbors:
		var ns := _same_terrain(cell + Vector2i.UP, terrain_id) or _same_terrain(cell + Vector2i.DOWN, terrain_id)
		var ew := _same_terrain(cell + Vector2i.LEFT, terrain_id) or _same_terrain(cell + Vector2i.RIGHT, terrain_id)
		return PI * 0.5 if ns and not ew else 0.0
	var h := absi(cell.x * 73856093 ^ cell.y * 19349663)
	return PI * 0.5 * float(h % 4)


func _same_terrain(cell: Vector2i, terrain_id: StringName) -> bool:
	return _tile_nodes.has(cell) and terrain_id_at(cell) == terrain_id


func _apply_overlay(cell: Vector2i) -> void:
	if not _overlay_nodes.has(cell):
		return
	var ov: Polygon2D = _overlay_nodes[cell] as Polygon2D
	var tag := ""
	if cell == _overlay_selected:
		tag = "s"
	elif _overlay_attack.has(cell):
		tag = "a"
	elif _overlay_move.has(cell):
		tag = "m"
	ov.visible = tag != ""
	if tag != "":
		ov.color = OVERLAY_COLORS.get(tag, Color(1, 1, 1, 0.4)) as Color


func _draw_depth_for_cell(cell: Vector2i) -> int:
	return (cell.x + cell.y) * DRAW_DEPTH_STRIDE


func _unit_pose_screen(cell: Vector2i) -> Dictionary:
	var unit_h: float = config.unit_world_height if config != null else 0.88
	var feet := _cell_ground_center(cell, config.cell_size)
	feet.y = config.tile_height + UNIT_FEET_LIFT
	var torso := feet + Vector3(0.0, unit_h * 0.5, 0.0)
	var head := feet + Vector3(0.0, unit_h * 0.92, 0.0)
	return {
		"feet": _oblique_project(feet),
		"torso": _oblique_project(torso),
		"head": _oblique_project(head),
	}


func _unit_local_pose_on_tile(cell: Vector2i) -> Dictionary:
	var center := _cell_to_world(cell, config.cell_size)
	var pose := _unit_pose_screen(cell)
	return {
		"feet": (pose["feet"] as Vector2) - center,
		"torso": (pose["torso"] as Vector2) - center,
		"head": (pose["head"] as Vector2) - center,
	}


func _unit_world_position(spr: Sprite2D) -> Vector2:
	var parent := spr.get_parent() as Node2D
	if parent == null:
		return spr.position
	return parent.position + spr.position


func _mount_unit_on_tile(unit: TacticalUnitInstance) -> void:
	var spr := _unit_sprites.get(unit) as Sprite2D
	if spr == null:
		return
	var tile: Node2D = _tile_nodes.get(unit.cell) as Node2D
	if tile == null:
		return
	if spr.get_parent() != tile:
		if spr.get_parent() != null:
			spr.reparent(tile, true)
		else:
			tile.add_child(spr)
	spr.z_index = UNIT_DRAW_LAYER
	spr.z_as_relative = true


func _float_unit_for_world_tween(spr: Sprite2D) -> void:
	if spr.get_parent() == _units_root:
		return
	spr.reparent(_units_root, true)


func _sync_unit_blob_pose(unit: TacticalUnitInstance, pose: Dictionary) -> void:
	if not _unit_blobs.has(unit):
		return
	var blob := _unit_blobs[unit] as Sprite2D
	blob.position = (pose["feet"] as Vector2) - (pose["torso"] as Vector2)


func _oblique_project(p: Vector3) -> Vector2:
	var pitch := deg_to_rad(config.camera_pitch_deg)
	var yaw := deg_to_rad(config.camera_yaw_deg)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var rx := cos(yaw)
	var rz := -sin(yaw)
	var fx := sin(yaw)
	var fz := cos(yaw)
	var sx := p.x * rx + p.z * rz
	var sy := -(p.x * fx + p.z * fz) * cp + p.y * sp
	return Vector2(sx, sy)


func _oblique_unproject_ground(screen: Vector2) -> Vector3:
	var pitch := deg_to_rad(config.camera_pitch_deg)
	var yaw := deg_to_rad(config.camera_yaw_deg)
	var cp := cos(pitch)
	var rx := cos(yaw)
	var rz := -sin(yaw)
	var fx := sin(yaw)
	var fz := cos(yaw)
	var det := rx * (-fz * cp) - rz * (-fx * cp)
	if absf(det) < 1e-8:
		return Vector3.ZERO
	var gx := (screen.x * (-fz * cp) - screen.y * rz) / det
	var gz := (rx * screen.y - screen.x * (-fx * cp)) / det
	return Vector3(gx, 0.0, gz)


func _cell_ground_center(cell: Vector2i, cell_size: float) -> Vector3:
	var ox := (float(config.grid_width) - 1.0) * 0.5
	var oy := (float(config.grid_height) - 1.0) * 0.5
	var x := (float(cell.x) - ox) * cell_size
	var z := (float(cell.y) - oy) * cell_size
	return Vector3(x, config.tile_height, z)


func _cell_ground_corner(cell: Vector2i, lx: float, lz: float) -> Vector3:
	var ox := (float(config.grid_width) - 1.0) * 0.5
	var oy := (float(config.grid_height) - 1.0) * 0.5
	var x := (float(cell.x) - ox) * config.cell_size + lx
	var z := (float(cell.y) - oy) * config.cell_size + lz
	return Vector3(x, config.tile_height, z)


func _project_poly_local(cell: Vector2i, corners_3d: Array) -> PackedVector2Array:
	var center := _cell_to_world(cell, config.cell_size)
	var out := PackedVector2Array()
	for c in corners_3d:
		out.append(_oblique_project(c as Vector3) - center)
	return out


func _update_tile_geometry(cell: Vector2i) -> void:
	if not _tile_nodes.has(cell):
		return
	var root: Node2D = _tile_nodes[cell] as Node2D
	var half := config.cell_size * config.tile_inset * 0.5
	var center_proj := _cell_to_world(cell, config.cell_size)
	root.position = center_proj
	var top_corners := [
		_cell_ground_corner(cell, -half, -half),
		_cell_ground_corner(cell, half, -half),
		_cell_ground_corner(cell, half, half),
		_cell_ground_corner(cell, -half, half),
	]
	var poly := _project_poly_local(cell, top_corners)
	var grass: Polygon2D = root.get_node("Grass") as Polygon2D
	grass.polygon = poly
	var ov: Polygon2D = root.get_node("Overlay") as Polygon2D
	ov.polygon = poly
	root.z_index = _draw_depth_for_cell(cell)
	_update_wall_geometry(cell, 0.0)


func _update_wall_geometry(cell: Vector2i, yaw_rad: float) -> void:
	var root: Node2D = _tile_nodes[cell] as Node2D
	var wall: Node2D = root.get_node_or_null("Wall") as Node2D
	if wall == null:
		return
	for ch in wall.get_children():
		ch.queue_free()
	var half := config.cell_size * config.tile_inset * 0.5
	var thick := config.cell_size * 0.16 * 0.5
	var cos_y := cos(yaw_rad)
	var sin_y := sin(yaw_rad)
	var corners_stone: Array = []
	for lc in [Vector2(-thick, -half), Vector2(thick, -half), Vector2(thick, half), Vector2(-thick, half)]:
		var lx2: float = lc.x * cos_y - lc.y * sin_y
		var lz2: float = lc.x * sin_y + lc.y * cos_y
		corners_stone.append(_cell_ground_corner(cell, lx2, lz2))
	var body := Polygon2D.new()
	body.name = "StoneBody"
	body.color = WALL_STONE_LIGHT
	body.polygon = _project_poly_local(cell, _quad_from_first4(corners_stone))
	wall.add_child(body)
	var stripe_corners := [
		corners_stone[0].lerp(corners_stone[1], 0.35),
		corners_stone[0].lerp(corners_stone[1], 0.65),
		corners_stone[3].lerp(corners_stone[2], 0.65),
		corners_stone[3].lerp(corners_stone[2], 0.35),
	]
	var stripe := Polygon2D.new()
	stripe.name = "StoneStripe"
	stripe.color = WALL_STONE_DARK
	stripe.polygon = _project_poly_local(cell, stripe_corners)
	wall.add_child(stripe)


func _quad_from_first4(points: Array) -> Array:
	return [points[0], points[1], points[3], points[2]]


func grass_color_at(cell: Vector2i) -> Color:
	if not _tile_nodes.has(cell):
		return Color.BLACK
	var root: Node2D = _tile_nodes[cell] as Node2D
	var grass: Polygon2D = root.get_node_or_null("Grass") as Polygon2D
	return grass.color if grass != null else Color.BLACK


func wall_rotation_at(cell: Vector2i) -> float:
	if not _tile_nodes.has(cell):
		return 0.0
	var root: Node2D = _tile_nodes[cell] as Node2D
	var wall: Node2D = root.get_node_or_null("Wall") as Node2D
	if wall == null or not wall.visible:
		return 0.0
	var terrain_id := terrain_id_at(cell)
	var def := _get_catalog().get_def(terrain_id)
	return _tile_yaw(cell, terrain_id, def)


func wall_footprint_size(cell: Vector2i) -> Vector2:
	if config == null or not _tile_nodes.has(cell):
		return Vector2.ZERO
	var cell_size := config.cell_size
	var inset := cell_size * config.tile_inset
	return Vector2(inset, cell_size * 0.16)


func _cell_to_world(cell: Vector2i, cell_size: float) -> Vector2:
	return _oblique_project(_cell_ground_center(cell, cell_size))


func _apply_camera() -> void:
	if _camera == null or _pivot == null or config == null:
		return
	_pivot.position = _oblique_project(Vector3(_target.x, 0.0, _target.z))
	var vs := _viewport.size if _viewport != null else Vector2i(852, 393)
	var vh := maxf(float(vs.y), 1.0)
	var ortho := maxf(config.camera_ortho_size, 0.1)
	var cam_zoom := vh * maxf(_zoom, 0.05) / ortho
	_camera.zoom = Vector2(cam_zoom, cam_zoom)
	_camera.offset = Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if config == null or _camera == null:
		return
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_set_zoom(_zoom * mg.factor)
		accept_event()
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(make_input_local(event) as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_handle_screen_drag(make_input_local(event) as InputEventScreenDrag)
		return
	if event is InputEventMouseButton:
		var mb := make_input_local(event) as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(_zoom * 1.1)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(_zoom / 1.1)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = false
				_drag_last = mb.position
				_press_pos = mb.position
			else:
				_dragging = false
				if not _drag_moved:
					_handle_click(mb.position)
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := make_input_local(event) as InputEventMouseMotion
		if _dragging and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var delta := mm.position - _drag_last
			_drag_last = mm.position
			if not _drag_moved and _press_pos.distance_to(mm.position) >= DRAG_THRESHOLD_PX:
				_drag_moved = true
			if _drag_moved:
				_pan_by_screen_delta(delta)
				accept_event()


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, config.camera_zoom_min, config.camera_zoom_max)
	_clamp_target()
	_apply_camera()


func _pan_by_screen_delta(delta: Vector2) -> void:
	_target += compute_pan_world_delta(delta)
	_clamp_target()
	_apply_camera()


func compute_pan_world_delta(delta: Vector2) -> Vector3:
	var sens := config.camera_pan_sensitivity / maxf(_zoom, 0.05)
	var cam_z := _camera.zoom.y if _camera != null and _camera.zoom.y > 0.0 else 1.0
	var scaled := delta / cam_z
	var yaw := deg_to_rad(config.camera_yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	return -right * scaled.x * sens - forward * scaled.y * sens


func _handle_screen_touch(st: InputEventScreenTouch) -> void:
	if st.pressed:
		_active_touches[st.index] = st.position
		if _active_touches.size() == 1:
			_touch_drag_index = st.index
			_dragging = true
			_drag_moved = false
			_drag_last = st.position
			_press_pos = st.position
		elif _active_touches.size() >= 2:
			_dragging = false
			_touch_drag_index = -1
			_pinch_last_distance = _pinch_distance()
	else:
		_active_touches.erase(st.index)
		if st.index == _touch_drag_index:
			if not _drag_moved and _active_touches.is_empty():
				_handle_click(st.position)
			_dragging = false
			_touch_drag_index = -1
		if _active_touches.size() < 2:
			_pinch_last_distance = 0.0
		elif _active_touches.size() == 1:
			var remaining: int = _active_touches.keys()[0]
			_touch_drag_index = remaining
			_dragging = true
			_drag_last = _active_touches[remaining]
			_press_pos = _drag_last
			_drag_moved = true
	accept_event()


func _handle_screen_drag(sd: InputEventScreenDrag) -> void:
	if _active_touches.has(sd.index):
		_active_touches[sd.index] = sd.position
	if _active_touches.size() >= 2:
		_apply_pinch_zoom()
		accept_event()
		return
	if not _dragging or sd.index != _touch_drag_index:
		return
	var delta := sd.position - _drag_last
	_drag_last = sd.position
	if not _drag_moved and _press_pos.distance_to(sd.position) >= DRAG_THRESHOLD_PX:
		_drag_moved = true
	if _drag_moved:
		_pan_by_screen_delta(delta)
	accept_event()


func _pinch_distance() -> float:
	var keys := _active_touches.keys()
	if keys.size() < 2:
		return 0.0
	var a: Vector2 = _active_touches[keys[0]]
	var b: Vector2 = _active_touches[keys[1]]
	return a.distance_to(b)


func _apply_pinch_zoom() -> void:
	var dist := _pinch_distance()
	if _pinch_last_distance > 1.0 and dist > 1.0:
		_set_zoom(_zoom * (dist / _pinch_last_distance))
	_pinch_last_distance = dist


func _handle_click(local_pos: Vector2) -> void:
	var cell: Variant = _pick_cell(local_pos)
	if cell == null:
		return
	cell_clicked.emit(cell as Vector2i)


func _pick_cell(local_pos: Vector2) -> Variant:
	if _camera == null or size.y <= 0.0 or not _camera.is_inside_tree():
		return null
	var vp_pos := _to_viewport_pos(local_pos)
	var inv := _camera.get_canvas_transform().affine_inverse()
	var hit: Vector2 = inv * vp_pos
	var ground := _oblique_unproject_ground(hit)
	return _world_to_cell(ground)


func _world_to_cell(world: Vector3) -> Variant:
	var cell_size := config.cell_size
	var ox := (float(config.grid_width) - 1.0) * 0.5
	var oy := (float(config.grid_height) - 1.0) * 0.5
	var gx := int(round(world.x / cell_size + ox))
	var gy := int(round(world.z / cell_size + oy))
	if gx < 0 or gy < 0 or gx >= config.grid_width or gy >= config.grid_height:
		return null
	return Vector2i(gx, gy)


func _to_viewport_pos(local_pos: Vector2) -> Vector2:
	if _viewport == null or _viewport_container == null:
		return local_pos
	var container_size := _viewport_container.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return local_pos
	var vs := _viewport.size
	if vs.x <= 0 or vs.y <= 0:
		return local_pos
	return Vector2(local_pos.x * vs.x / container_size.x, local_pos.y * vs.y / container_size.y)


func _clamp_target() -> void:
	var cell_size := config.cell_size
	var half_w := float(config.grid_width) * cell_size * 0.5
	var half_h := float(config.grid_height) * cell_size * 0.5
	var pad := cell_size * 1.5
	_target.x = clampf(_target.x, -half_w - pad, half_w + pad)
	_target.z = clampf(_target.z, -half_h - pad, half_h + pad)
	_target.y = 0.0