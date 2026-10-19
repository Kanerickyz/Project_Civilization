class_name GridBoardView
extends Control
## 斜 45° 正交俯视方格盘：3D 格块 + Sprite3D 占位单位；拖拽/滚轮镜头。


signal cell_clicked(cell: Vector2i)

var config: BoardConfig

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world_root: Node3D
var _tiles_root: Node3D
var _units_root: Node3D
var _camera: Camera3D
var _pivot: Node3D
var _tile_nodes: Dictionary = {} # Vector2i -> MeshInstance3D
var _overlay_nodes: Dictionary = {} # Vector2i -> MeshInstance3D
var _fallback_mesh_cache: Dictionary = {} # String -> BoxMesh
var _fallback_mat_cache: Dictionary = {} # StringName -> StandardMaterial3D
var _grass_checker_mats: Dictionary = {} # int parity -> ShaderMaterial
var _overlay_mat_cache: Dictionary = {} # String tag -> StandardMaterial3D
var _overlay_mesh: PlaneMesh
var _catalog: TerrainCatalog
var _key_light: DirectionalLight3D
var _environment: Environment
var _blob_mesh: PlaneMesh
var _blob_material: StandardMaterial3D

var _target: Vector3 = Vector3.ZERO
var _zoom: float = 1.0
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _press_pos: Vector2 = Vector2.ZERO
var _needs_center: bool = true

const DRAG_THRESHOLD_PX := 6.0
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const OVERLAY_LIFT := 0.005
const BLOB_LIFT := 0.02
const BLOB_HIDE_ALPHA := 0.6
const OVERLAY_COLORS := {
	"s": Color(0.35, 0.56, 0.83, 0.5),
	"m": Color(0.42, 1.0, 0.72, 0.58),
	"a": Color(0.82, 0.28, 0.31, 0.5),
}
## 草地棋盘格：浅 / 深（按格 (x+y)%2）；城墙等地块用 catalog 原材质。
const GRASS_CHECKER_LIGHT := Color("B4A158")
const GRASS_CHECKER_DARK := Color("8F884C")

var _terrain_cells: Dictionary = {} # Vector2i -> StringName（TerrainTypeDef.id）

var _unit_sprites: Dictionary = {} # TacticalUnitInstance -> Sprite3D
var _overlay_selected: Vector2i = Vector2i(-1, -1)
var _overlay_move: Dictionary = {}
var _overlay_attack: Dictionary = {}

var _last_unit_cells: Dictionary = {} # TacticalUnitInstance -> Vector2i
var _hp_bars: Dictionary = {} # TacticalUnitInstance -> Label3D
var _unit_blobs: Dictionary = {} # TacticalUnitInstance -> MeshInstance3D

var _touch_drag_index: int = -1
var _active_touches: Dictionary = {} # int index -> Vector2 position
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


## cells: Vector2i -> StringName 地块 id；未列出的格为 catalog.default_id。
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
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport_container.add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "BoardWorld"
	_viewport.add_child(_world_root)

	_key_light = DirectionalLight3D.new()
	_key_light.name = "KeyLight"
	_world_root.add_child(_key_light)

	var world_env := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.environment = _environment
	_world_root.add_child(world_env)

	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_world_root.add_child(_pivot)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 10.5
	_camera.near = 0.05
	_camera.far = 200.0
	_pivot.add_child(_camera)

	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	_world_root.add_child(_tiles_root)

	_units_root = Node3D.new()
	_units_root.name = "Units"
	_world_root.add_child(_units_root)


func _look() -> BoardLook:
	if config != null and config.look != null:
		return config.look
	return BoardLook.new()


## 暖色主光 + 冷色天光（环境光）+ 柔和投影 + tonemap / 调色。Compatibility 与 Web 均支持；
## Web 回退见 BoardLook.shadow_active() / post_adjust_active()。
func _apply_look() -> void:
	if _key_light == null or _environment == null:
		return
	var look := _look()
	_key_light.rotation_degrees = Vector3(look.key_pitch_deg, look.key_yaw_deg, 0.0)
	_key_light.light_color = look.key_color
	_key_light.light_energy = look.key_energy
	_key_light.shadow_enabled = look.shadow_active()
	_key_light.shadow_opacity = look.shadow_opacity
	_key_light.shadow_blur = look.shadow_blur
	_key_light.shadow_bias = look.shadow_bias
	_key_light.shadow_normal_bias = look.shadow_normal_bias
	_key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_key_light.directional_shadow_max_distance = look.shadow_max_distance
	_environment.background_color = look.background_color
	_environment.ambient_light_color = look.ambient_color
	_environment.ambient_light_energy = look.ambient_energy
	_environment.tonemap_mode = look.tonemap_mode
	_environment.tonemap_exposure = look.tonemap_exposure
	_environment.tonemap_white = look.tonemap_white
	_environment.adjustment_enabled = look.post_adjust_active()
	_environment.adjustment_brightness = look.adjust_brightness
	_environment.adjustment_contrast = look.adjust_contrast
	_environment.adjustment_saturation = look.adjust_saturation
	_blob_mesh = null
	_blob_material = null


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
	var center := _cell_to_world(
		Vector2i(config.grid_width / 2, config.grid_height / 2), config.cell_size
	)
	_target = Vector3(center.x, 0.0, center.z)
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
	_overlay_mesh = PlaneMesh.new()
	_overlay_mesh.size = Vector2.ONE * cell_size * config.tile_inset
	for gx in range(config.grid_width):
		for gy in range(config.grid_height):
			var cell := Vector2i(gx, gy)
			var mi := MeshInstance3D.new()
			mi.name = "Tile_%d_%d" % [gx, gy]
			mi.position = _cell_to_world(cell, cell_size)
			_tiles_root.add_child(mi)
			_tile_nodes[cell] = mi
			var ov := MeshInstance3D.new()
			ov.name = "Overlay_%d_%d" % [gx, gy]
			ov.mesh = _overlay_mesh
			ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ov.position = Vector3(mi.position.x, config.tile_height + OVERLAY_LIFT, mi.position.z)
			ov.visible = false
			_tiles_root.add_child(ov)
			_overlay_nodes[cell] = ov
	for cell in _tile_nodes.keys():
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
	var spr := _unit_sprites[unit] as Sprite3D
	var world := _cell_to_world(unit.cell, config.cell_size)
	var unit_h: float = config.unit_world_height if config != null else 0.88
	var target_pos := Vector3(world.x, config.tile_height + unit_h * 0.5, world.z)
	var prev: Variant = _last_unit_cells.get(unit, unit.cell)
	_last_unit_cells[unit] = unit.cell
	if prev is Vector2i and prev != unit.cell and is_inside_tree():
		_tween_unit_to(spr, target_pos)
	else:
		spr.position = target_pos
	_update_hp_bar(unit)


const UNIT_MOVE_TWEEN_SEC := 0.26


func unit_move_duration_sec() -> float:
	return UNIT_MOVE_TWEEN_SEC


func _tween_unit_to(spr: Sprite3D, target_pos: Vector3) -> void:
	var tw := create_tween()
	tw.tween_property(spr, "position", target_pos, UNIT_MOVE_TWEEN_SEC).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)


func play_unit_attack(attacker: TacticalUnitInstance, target_cell: Vector2i) -> Tween:
	if config == null or not _unit_sprites.has(attacker):
		return null
	var spr := _unit_sprites[attacker] as Sprite3D
	var home := spr.position
	var world := _cell_to_world(target_cell, config.cell_size)
	var flat := Vector3(world.x - home.x, 0.0, world.z - home.z)
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
		var spr: Sprite3D = _unit_sprites[unit] as Sprite3D
		spr.queue_free()
		_unit_sprites.erase(unit)
	if _unit_blobs.has(unit):
		(_unit_blobs[unit] as Node).queue_free()
		_unit_blobs.erase(unit)
	if _hp_bars.has(unit):
		var bar: Label3D = _hp_bars[unit] as Label3D
		bar.queue_free()
		_hp_bars.erase(unit)
	_last_unit_cells.erase(unit)


func play_damage_popup(cell: Vector2i, amount: int) -> void:
	if config == null or _units_root == null:
		return
	var world := _cell_to_world(cell, config.cell_size)
	var lbl := Label3D.new()
	lbl.text = "-%d!" % amount
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 24
	lbl.modulate = Color("ff6644")
	lbl.outline_modulate = Color("1a0808")
	var lift: float = config.tile_height + config.unit_world_height * 0.85
	lbl.position = Vector3(world.x, lift, world.z)
	_units_root.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y + 0.75, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.45).set_delay(0.12)
	tw.finished.connect(lbl.queue_free)


func play_unit_hit(unit: TacticalUnitInstance) -> void:
	if not _unit_sprites.has(unit):
		return
	var spr := _unit_sprites[unit] as Sprite3D
	var base := spr.position
	spr.modulate = Color("ff8888")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "modulate", _look().unit_modulate, 0.32)
	tw.tween_property(spr, "position:x", base.x + 0.06, 0.06).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(spr, "position", base, 0.12).set_trans(Tween.TRANS_SINE)


func play_unit_death(unit: TacticalUnitInstance) -> void:
	if not _unit_sprites.has(unit):
		return
	var spr := _unit_sprites[unit] as Sprite3D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", Vector3(0.05, 0.05, 0.05), 0.32)
	tw.tween_property(spr, "modulate:a", 0.0, 0.32)


func _ensure_unit_sprite(unit: TacticalUnitInstance) -> void:
	var spr: Sprite3D
	if _unit_sprites.has(unit):
		spr = _unit_sprites[unit] as Sprite3D
	else:
		spr = Sprite3D.new()
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 透明像素不写深度，脚下软影才不会被整张卡片挡住。
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		spr.name = "Unit_%s_%s" % [unit.def.id, unit.faction]
		_units_root.add_child(spr)
		_unit_sprites[unit] = spr
		_attach_unit_blob(unit)
	var tex := unit.def.texture_blue
	if unit.faction == TacticalFactionScript.Id.OPPONENT:
		tex = unit.def.texture_red
	var unit_h: float = config.unit_world_height
	var tex_h := float(tex.get_height())
	if tex_h > 0.0:
		spr.pixel_size = unit_h / tex_h
	spr.texture = tex
	spr.modulate = _look().unit_modulate if unit.is_alive() else Color(0.4, 0.4, 0.4, 0.5)
	spr.scale = Vector3.ONE
	_ensure_hp_bar(unit)


## 脚下软影：与 Sprite 同级（挂在 Sprite 下时会被 billboard 卡片吞掉），每帧跟随其水平位置 / 缩放；
## Compatibility 不支持 GeometryInstance3D.transparency，Sprite 半透（阵亡灰化 / 死亡淡出）时直接隐藏。
func _attach_unit_blob(unit: TacticalUnitInstance) -> void:
	var look := _look()
	if look.unit_blob_opacity <= 0.0:
		return
	if _blob_mesh == null:
		_blob_mesh = PlaneMesh.new()
		_blob_mesh.size = Vector2.ONE * look.unit_blob_radius * 2.0 * config.cell_size
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
		_blob_material = StandardMaterial3D.new()
		_blob_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_material.albedo_texture = tex
		# 透明物按 render_priority 先排：高亮(-2) → 软影(-1) → 角色(0)，避免被 Sprite 深度挡住。
		_blob_material.render_priority = -1
	var blob := MeshInstance3D.new()
	blob.name = "Blob"
	blob.mesh = _blob_mesh
	blob.material_override = _blob_material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_units_root.add_child(blob)
	_unit_blobs[unit] = blob


func _process(_delta: float) -> void:
	for unit in _unit_blobs:
		var spr := _unit_sprites.get(unit) as Sprite3D
		if spr == null:
			continue
		var blob := _unit_blobs[unit] as MeshInstance3D
		var s := spr.scale.x
		blob.position = Vector3(spr.position.x, config.tile_height + BLOB_LIFT, spr.position.z)
		blob.scale = Vector3(s, 1.0, s * 0.7)
		blob.visible = spr.modulate.a > BLOB_HIDE_ALPHA


func _ensure_hp_bar(unit: TacticalUnitInstance) -> void:
	var bar: Label3D
	if _hp_bars.has(unit):
		bar = _hp_bars[unit] as Label3D
	else:
		bar = Label3D.new()
		bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bar.font_size = 14
		bar.outline_size = 4
		bar.outline_modulate = Color("0a1018")
		_units_root.add_child(bar)
		_hp_bars[unit] = bar
	_update_hp_bar(unit)


func _update_hp_bar(unit: TacticalUnitInstance) -> void:
	if not _hp_bars.has(unit) or not _unit_sprites.has(unit):
		return
	var bar := _hp_bars[unit] as Label3D
	var spr := _unit_sprites[unit] as Sprite3D
	bar.text = "%d/%d" % [unit.hp, unit.def.max_hp]
	var bar_lift: float = config.unit_world_height * 0.48
	bar.position = spr.position + Vector3(0.0, bar_lift, 0.0)
	if unit.hp <= unit.def.max_hp / 3:
		bar.modulate = Color("ff6666")
	else:
		bar.modulate = Color("e8f0ff")


func _terrain_surface_material(cell: Vector2i, terrain_id: StringName, def: TerrainTypeDef, surface: int) -> Material:
	if def.surface_materials.size() <= surface:
		return null
	var base: Material = def.surface_materials[surface]
	if surface == 0 and _uses_grass_checker(terrain_id):
		var parity: int = (cell.x + cell.y) & 1
		return _grass_checker_material(parity, base)
	return base


func _uses_grass_checker(terrain_id: StringName) -> bool:
	return terrain_id == _get_catalog().default_id


func _grass_checker_material(parity: int, base: Material) -> ShaderMaterial:
	if _grass_checker_mats.has(parity):
		return _grass_checker_mats[parity] as ShaderMaterial
	var dup := (base as ShaderMaterial).duplicate() as ShaderMaterial
	var tint := GRASS_CHECKER_DARK if parity == 1 else GRASS_CHECKER_LIGHT
	dup.set_shader_parameter(&"albedo_tint", tint)
	_grass_checker_mats[parity] = dup
	return dup


func _apply_tile_visual(cell: Vector2i) -> void:
	if config == null or not _tile_nodes.has(cell):
		return
	var mi: MeshInstance3D = _tile_nodes[cell] as MeshInstance3D
	var terrain_id := terrain_id_at(cell)
	var def := _get_catalog().get_def(terrain_id)
	if def != null and def.mesh != null:
		if mi.mesh != def.mesh:
			mi.mesh = def.mesh
		for i in def.mesh.get_surface_count():
			var mat: Material = _terrain_surface_material(cell, terrain_id, def, i)
			mi.set_surface_override_material(i, mat)
	else:
		mi.mesh = _fallback_mesh()
		mi.set_surface_override_material(0, _fallback_material(terrain_id, def))
	mi.rotation = Vector3(0.0, _tile_yaw(cell, terrain_id, def), 0.0)
	_apply_overlay(cell)


## 直线型地块：仅南北有同类且东西都无同类时转 90°；其余地块按格哈希旋转 90° 倍数以打散重复纹样。
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
	var ov: MeshInstance3D = _overlay_nodes[cell] as MeshInstance3D
	var tag := ""
	if cell == _overlay_selected:
		tag = "s"
	elif _overlay_attack.has(cell):
		tag = "a"
	elif _overlay_move.has(cell):
		tag = "m"
	ov.visible = tag != ""
	if tag != "":
		ov.material_override = _overlay_material(tag)


func _overlay_material(tag: String) -> StandardMaterial3D:
	if _overlay_mat_cache.has(tag):
		return _overlay_mat_cache[tag] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = OVERLAY_COLORS.get(tag, Color(1, 1, 1, 0.4)) as Color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -2
	_overlay_mat_cache[tag] = mat
	return mat


func _fallback_mesh() -> BoxMesh:
	var inset := config.cell_size * config.tile_inset
	var key := "%.3f_%.3f" % [inset, config.tile_height]
	if not _fallback_mesh_cache.has(key):
		var box := BoxMesh.new()
		box.size = Vector3(inset, config.tile_height, inset)
		_fallback_mesh_cache[key] = box
	return _fallback_mesh_cache[key] as BoxMesh


func _fallback_material(terrain_id: StringName, def: TerrainTypeDef) -> StandardMaterial3D:
	if _fallback_mat_cache.has(terrain_id):
		return _fallback_mat_cache[terrain_id] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.editor_color if def != null else Color("6f9a3c")
	mat.roughness = 0.9
	_fallback_mat_cache[terrain_id] = mat
	return mat


func _cell_to_world(cell: Vector2i, cell_size: float) -> Vector3:
	var ox := (float(config.grid_width) - 1.0) * 0.5
	var oy := (float(config.grid_height) - 1.0) * 0.5
	var x := (float(cell.x) - ox) * cell_size
	var z := (float(cell.y) - oy) * cell_size
	return Vector3(x, config.tile_height * 0.5, z)


func _apply_camera() -> void:
	if _camera == null or _pivot == null or config == null:
		return
	_pivot.position = _target
	_pivot.rotation = Vector3.ZERO
	var elev := deg_to_rad(config.camera_pitch_deg)
	var yaw := deg_to_rad(config.camera_yaw_deg)
	var dist := config.camera_distance
	var offset := Vector3(
		dist * cos(elev) * sin(yaw),
		dist * sin(elev),
		dist * cos(elev) * cos(yaw)
	)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = config.camera_ortho_size / maxf(_zoom, 0.05)
	_camera.transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), offset)


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


## 供 headless 烟测：屏幕位移对应的地面平移（指拖地图，非相机反移）。
func compute_pan_world_delta(delta: Vector2) -> Vector3:
	var sens := config.camera_pan_sensitivity / maxf(_zoom, 0.05)
	var yaw := deg_to_rad(config.camera_yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	return -right * delta.x * sens - forward * delta.y * sens


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
	var from := _camera.project_ray_origin(vp_pos)
	var dir := _camera.project_ray_normal(vp_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	var hit := from + dir * t
	return _world_to_cell(Vector3(hit.x, 0.0, hit.z))


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
