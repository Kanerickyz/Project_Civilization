class_name GridBoardView
extends Control
## 2D 方格盘（斜 45° 正交投影）：Polygon2D 格块 + Sprite2D 单位；Camera2D 拖拽/滚轮。


signal cell_clicked(cell: Vector2i)
## 长按单位约 0.38s（对照 autochess LONG_PRESS_MS）；松手发 unit_info_closed。
signal unit_long_pressed(unit: TacticalUnitInstance, anchor_global: Vector2)
signal unit_info_closed
## 部署阶段：拖起己方单位后松手落格（cell 越界则为无效，由沙盘校验）。
signal unit_deploy_dropped(unit: TacticalUnitInstance, cell: Vector2i)

var config: BoardConfig

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _chrome: ColorRect ## Control 层底色，避免 SubViewport 未铺满时透出沙盘灰底。
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
const LONG_PRESS_SEC := 0.38
const LONG_PRESS_SLOP_PX := 10.0
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const GridPathfindingScript := preload("res://scripts/units/grid_pathfinding.gd")
const UI_FONT := preload("res://resources/ui/ui_font.tres")
const HIT_FLASH_SHADER := preload("res://resources/units/shaders/unit_hit_flash.gdshader")
const OVERLAY_Z := 4
const WALL_Z := 2
const GRASS_Z := 0
## 地块按屏幕纵深；单位用绝对 z，整层高于任何格子，彼此再按脚底屏幕 Y 排序。
const DRAW_DEPTH_STRIDE := 16
const UNIT_Z_BASE := 1000
## 移动表现（对齐 autochess UnitBoardDisplay.play_move_to）：逐格 hop + 微抬升。
const UNIT_MOVE_HOP_SEC := 0.18
const UNIT_MOVE_HOP_HEIGHT_FRAC := 0.12
const OVERLAY_COLORS := {
	"s": Color(0.35, 0.56, 0.83, 0.5),
	"m": Color(0.42, 1.0, 0.72, 0.58),
	"a": Color(0.82, 0.28, 0.31, 0.5),
	## 拖牌悬停：可落 vs 不可落（范围外/错误目标仍标出当前格）。
	"h": Color(1.0, 0.88, 0.28, 0.42),
	"hv": Color(0.38, 0.95, 0.55, 0.55),
	"hx": Color(0.78, 0.32, 0.36, 0.42),
	## 点燃地块（可与选中/移动/攻击叠显：独立 marker，本色仅作参考）。
	"b": Color(1.0, 0.42, 0.12, 0.38),
}
const BURN_MARKER_COLOR := Color(1.0, 0.45, 0.1, 0.72)
const BURN_MARKER_CORE := Color(1.0, 0.85, 0.35, 0.9)
const BURN_BADGE_COLOR := Color("ff7a2e")
const BURN_MARKER_Z := 3
const BURN_MARKER_PULSE_SEC := 0.55
const GRASS_CHECKER_LIGHT := Color("B4A158")
const GRASS_CHECKER_DARK := Color("8F884C")
const WALL_STONE_LIGHT := Color("9c958c")
const WALL_STONE_DARK := Color("716c65")

var _terrain_cells: Dictionary = {} # Vector2i -> StringName

var _unit_sprites: Dictionary = {} # TacticalUnitInstance -> Sprite2D
var _overlay_selected: Vector2i = Vector2i(-1, -1)
var _overlay_move: Dictionary = {}
var _overlay_attack: Dictionary = {}
## 拖牌悬停当前格；(-1,-1) 表示无。
var _overlay_drag_hover: Vector2i = Vector2i(-1, -1)
## 0=空白/中性，1=可落单位，-1=不可落单位。
var _overlay_drag_hover_kind: int = 0

var _last_unit_cells: Dictionary = {}
var _unit_move_tweens: Dictionary = {} # TacticalUnitInstance -> Tween
var _last_move_tween_sec: float = UNIT_MOVE_HOP_SEC
var _hp_bars: Dictionary = {} # TacticalUnitInstance -> Label（常驻 HP + 攻）
var _burn_badges: Dictionary = {} # TacticalUnitInstance -> Label（燃N）
var _burn_markers: Dictionary = {} # Vector2i -> Node2D（点燃地块标记）
var _overlay_burn: Dictionary = {} # Vector2i -> true
var _burn_pulse_tween: Tween
var _unit_blobs: Dictionary = {} # TacticalUnitInstance -> Sprite2D
var _blob_texture: Texture2D
## 待机浮动只改 offset，不碰 position，避免挡移动/冲刺/受击 Tween 与格子点选。
var _unit_idle_tweens: Dictionary = {} # TacticalUnitInstance -> Tween
var _unit_base_offsets: Dictionary = {} # TacticalUnitInstance -> Vector2
## 拖牌悬停选中只改 scale，不碰 offset/position/modulate（避 idle bob / hit flash）。
var _unit_select_tweens: Dictionary = {} # TacticalUnitInstance -> Tween
var _unit_base_scales: Dictionary = {} # TacticalUnitInstance -> Vector2
## Texture2D -> {content_h: float, offset_y: float}；按不透明区域算缩放/脚点。
var _tex_content_cache: Dictionary = {}
var _drag_select_unit: TacticalUnitInstance = null
var _drag_select_valid: bool = false
var _long_press_timer: Timer
var _press_unit: TacticalUnitInstance = null
var _info_shown: bool = false
var _suppress_click: bool = false
## 开战前部署：按住己方单位拖到落点；空地仍可平移镜头。
var _deploy_mode: bool = false
var _deploy_valid_cells: Dictionary = {} # Vector2i -> true
var _deploy_drag_unit: TacticalUnitInstance = null

const UNIT_IDLE_BOB_PX := 3.0
const UNIT_IDLE_HALF_SEC := 0.95
const UNIT_SELECT_SCALE_VALID := 1.14
const UNIT_SELECT_SCALE_INVALID := 1.08
const UNIT_SELECT_HALF_SEC := 0.22

var _touch_drag_index: int = -1
var _active_touches: Dictionary = {}
var _pinch_last_distance: float = 0.0


func setup(p_config: BoardConfig) -> void:
	config = p_config
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_viewport_tree()
	_ensure_long_press_timer()
	_apply_look()
	_zoom = clampf(config.camera_zoom_default, _effective_zoom_min(), config.camera_zoom_max)
	_needs_center = true
	_rebuild_board()
	_try_center_on_board()
	_apply_camera()


## 部署模式：仅己方单位可拖；valid_cells 为合法落点（用于悬停色）。
func set_deploy_mode(enabled: bool, valid_cells: Array = []) -> void:
	_deploy_mode = enabled
	_deploy_valid_cells.clear()
	for c in valid_cells:
		if c is Vector2i:
			_deploy_valid_cells[c as Vector2i] = true
	if not enabled:
		_clear_deploy_drag()
		clear_card_drag_hover()


func is_deploy_mode() -> bool:
	return _deploy_mode


func _clear_deploy_drag() -> void:
	if _deploy_drag_unit != null and _unit_sprites.has(_deploy_drag_unit):
		_snap_unit_to_cell_center(_deploy_drag_unit)
		if _deploy_drag_unit.is_alive():
			_ensure_unit_idle(_deploy_drag_unit)
	_deploy_drag_unit = null


func _ensure_long_press_timer() -> void:
	if _long_press_timer != null:
		return
	_long_press_timer = Timer.new()
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = LONG_PRESS_SEC
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)


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
	# Control 层先铺 BoardLook 底色：Web/竖屏下 stretch 同步前也不透出沙盘灰，避免「1/4 绿」。
	_chrome = ColorRect.new()
	_chrome.name = "BoardChrome"
	_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chrome)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# stretch=true：容器负责把 SubViewport 拉满；勿手改 size（引擎会忽略并留下未铺满绿块）。
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
	var bg := _look().background_color
	if _chrome != null:
		_chrome.color = bg
	if _backdrop != null:
		_backdrop.color = bg
	_blob_texture = null


func _on_resized() -> void:
	if config == null:
		return
	if _needs_center:
		_try_center_on_board()
	# 竖/横切换后「看全盘」所需下限会变；夹回有效区间以免卡在旧下限之上。
	_zoom = clampf(_zoom, _effective_zoom_min(), config.camera_zoom_max)
	_clamp_target()
	_apply_camera()


func recenter_camera() -> void:
	_needs_center = true
	_try_center_on_board()


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
	var moving_units: Array = _unit_move_tweens.keys()
	for key in moving_units:
		_kill_unit_move_tween(key as TacticalUnitInstance)
	_drag_select_unit = null
	_drag_select_valid = false
	_overlay_drag_hover = Vector2i(-1, -1)
	_overlay_drag_hover_kind = 0
	_clear_deploy_drag()
	for key in _unit_sprites.keys():
		_kill_unit_idle(key as TacticalUnitInstance)
		_kill_unit_select_tween(key as TacticalUnitInstance)
		(_unit_sprites[key] as Node).queue_free()
	for child in _tiles_root.get_children():
		child.queue_free()
	for child in _units_root.get_children():
		child.queue_free()
	_tile_nodes.clear()
	_overlay_nodes.clear()
	_unit_sprites.clear()
	_unit_blobs.clear()
	for key in _hp_bars.keys():
		var hp_lbl: Label = _hp_bars[key] as Label
		if hp_lbl != null and is_instance_valid(hp_lbl):
			hp_lbl.queue_free()
	_hp_bars.clear()
	for key in _burn_badges.keys():
		var burn_lbl: Label = _burn_badges[key] as Label
		if burn_lbl != null and is_instance_valid(burn_lbl):
			burn_lbl.queue_free()
	_burn_badges.clear()
	_clear_burn_markers()
	_overlay_burn.clear()
	_last_unit_cells.clear()
	_unit_move_tweens.clear()
	_unit_idle_tweens.clear()
	_unit_select_tweens.clear()
	_unit_base_offsets.clear()
	_unit_base_scales.clear()
	_tex_content_cache.clear()

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

			var forest := Node2D.new()
			forest.name = "Forest"
			forest.z_index = WALL_Z
			forest.visible = false
			root.add_child(forest)

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
	attack_cells: Array,
	ignited_cells: Array = []
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
	_overlay_burn.clear()
	for c in ignited_cells:
		if c is Vector2i:
			_overlay_burn[c] = true
	_sync_burn_markers()
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
	# 逻辑格已变且正在播移动 Tween 时，勿再 sync（否则会 kill tween 并瞬移到终点）。
	if _unit_move_tweens.has(unit):
		_update_hp_bar(unit)
		_update_burn_badge(unit)
		return
	var prev: Variant = _last_unit_cells.get(unit, unit.cell)
	_last_unit_cells[unit] = unit.cell
	_apply_unit_draw_depth(unit)
	if prev is Vector2i and prev != unit.cell and is_inside_tree():
		_pause_unit_idle(unit)
		_float_unit_for_world_tween(spr)
		_tween_unit_along_path(spr, prev as Vector2i, unit.cell, unit)
	else:
		_kill_unit_move_tween(unit)
		_mount_unit_on_tile(unit)
		spr.position = Vector2.ZERO
		_place_unit_blob(unit)
		_ensure_unit_idle(unit)
	_update_hp_bar(unit)


## 受击/冲刺位移相对 cell_size 的上限（世界单位；旧 +4.0 在 cell_size=1 时飞出数格）。
const UNIT_HIT_SHAKE_FRAC := 0.08
const UNIT_ATTACK_LUNGE_FRAC := 0.28
## 受击纯白闪：仅命中瞬间挂 flash shader；平时 material=null，走默认 Sprite2D 着色（避免常驻 shader 压暗）。
const UNIT_HIT_FLASH_HOLD_SEC := 0.08
const UNIT_HIT_FLASH_FADE_SEC := 0.22
const DAMAGE_POPUP_FONT_SIZE := 28
const DAMAGE_POPUP_LIFT_PX := 56.0


func unit_move_duration_sec() -> float:
	return _last_move_tween_sec


func unit_hit_shake_px(cell_size: float = -1.0) -> float:
	var cs := cell_size if cell_size > 0.0 else (config.cell_size if config != null else 1.0)
	return cs * UNIT_HIT_SHAKE_FRAC


func unit_attack_lunge_cap(cell_size: float = -1.0) -> float:
	var cs := cell_size if cell_size > 0.0 else (config.cell_size if config != null else 1.0)
	return cs * UNIT_ATTACK_LUNGE_FRAC


func _tween_unit_along_path(
	spr: Sprite2D, from_cell: Vector2i, to_cell: Vector2i, unit: TacticalUnitInstance
) -> void:
	_kill_unit_move_tween(unit)
	var path := _resolve_move_path(from_cell, to_cell)
	if path.size() < 2:
		path = [from_cell, to_cell] as Array[Vector2i]
	var hops := path.size() - 1
	_last_move_tween_sec = UNIT_MOVE_HOP_SEC * float(hops)
	var tw := create_tween()
	_unit_move_tweens[unit] = tw
	for i in hops:
		var start_w := spr.position if i == 0 else _cell_to_world(path[i], config.cell_size)
		var end_w := _cell_to_world(path[i + 1], config.cell_size)
		# tween_method 把插值作为第 1 个实参；bind 的参数接在后面。
		tw.tween_method(
			_apply_move_hop.bind(spr, start_w, end_w),
			0.0,
			1.0,
			UNIT_MOVE_HOP_SEC
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func() -> void:
		_unit_move_tweens.erase(unit)
		if not is_instance_valid(spr) or not _unit_sprites.has(unit):
			return
		_mount_unit_on_tile(unit)
		spr.position = Vector2.ZERO
		_place_unit_blob(unit)
		_apply_unit_draw_depth(unit)
		_update_hp_bar(unit)
		_ensure_unit_idle(unit)
	)


func _apply_move_hop(t: float, spr: Sprite2D, start_w: Vector2, end_w: Vector2) -> void:
	if spr == null or not is_instance_valid(spr) or config == null:
		return
	var u := clampf(t, 0.0, 1.0)
	var flat := start_w.lerp(end_w, u)
	var hop := sin(u * PI) * config.cell_size * UNIT_MOVE_HOP_HEIGHT_FRAC
	spr.position = flat - Vector2(0.0, hop)
	spr.z_as_relative = false
	spr.z_index = UNIT_Z_BASE + int(round(spr.position.y * 100.0))


func _resolve_move_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return GridPathfindingScript.shortest_path(from_cell, to_cell, _view_cell_passable)


func _view_cell_passable(cell: Vector2i) -> bool:
	if config == null:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= config.grid_width or cell.y >= config.grid_height:
		return false
	return _get_catalog().is_passable(terrain_id_at(cell))


func _kill_unit_move_tween(unit: TacticalUnitInstance) -> void:
	if not _unit_move_tweens.has(unit):
		return
	var tw: Tween = _unit_move_tweens[unit] as Tween
	_unit_move_tweens.erase(unit)
	if tw != null and tw.is_valid():
		tw.kill()


func play_unit_attack(attacker: TacticalUnitInstance, target_cell: Vector2i) -> Tween:
	if config == null or not _unit_sprites.has(attacker):
		return null
	_pause_unit_idle(attacker)
	var spr := _unit_sprites[attacker] as Sprite2D
	var home := _unit_combat_home(attacker, spr)
	spr.position = home
	var delta := _cell_to_world(target_cell, config.cell_size) - _cell_to_world(attacker.cell, config.cell_size)
	var lunge := home
	if delta.length_squared() > 0.0001:
		lunge = home + delta.normalized() * minf(delta.length() * 0.42, unit_attack_lunge_cap())
	var tw := create_tween()
	tw.tween_property(spr, "position", lunge, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 不用 TRANS_BACK：回弹会短暂越过格心。
	tw.tween_property(spr, "position", home, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func() -> void:
		if not is_instance_valid(spr) or not _unit_sprites.has(attacker):
			return
		_snap_unit_to_cell_center(attacker)
		_ensure_unit_idle(attacker)
	)
	return tw


func attack_tween_duration_sec() -> float:
	return 0.28


func _remove_unit_visual(unit: TacticalUnitInstance) -> void:
	if _drag_select_unit == unit:
		_drag_select_unit = null
		_drag_select_valid = false
	_kill_unit_move_tween(unit)
	_kill_unit_idle(unit)
	_kill_unit_select_tween(unit)
	_unit_base_offsets.erase(unit)
	_unit_base_scales.erase(unit)
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
	if _burn_badges.has(unit):
		var badge: Label = _burn_badges[unit] as Label
		badge.queue_free()
		_burn_badges.erase(unit)
	_last_unit_cells.erase(unit)


func play_damage_popup(cell: Vector2i, amount: int) -> void:
	if config == null:
		return
	# 与常驻 HP 读数同一套世界坐标（格心投影 + 头顶偏移），勿再抬 3D Y / 混像素。
	var world := _cell_to_world(cell, config.cell_size)
	var head := Vector2(0.0, -config.unit_world_height * 1.35)
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "-%d" % maxi(0, amount)
	lbl.add_theme_font_override("font", UI_FONT)
	lbl.add_theme_font_size_override("font_size", DAMAGE_POPUP_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color("ff5533"))
	lbl.add_theme_color_override("font_outline_color", Color("1a0a08"))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)
	lbl.scale = Vector2(0.55, 0.55)
	_labels_root.add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size * 0.5
	_position_world_on_label(lbl, world + head)
	_clamp_label_in_viewport(lbl)
	var start_pos := lbl.position
	var tw := create_tween()
	tw.set_parallel(true)
	# 上浮在屏幕空间（Control.position），不再经 world→screen。
	tw.tween_property(lbl, "position", start_pos + Vector2(0.0, -DAMAGE_POPUP_LIFT_PX), 0.55).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector2(1.12, 1.12), 0.14).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.38).set_delay(0.2)
	tw.finished.connect(lbl.queue_free)


func play_unit_hit(unit: TacticalUnitInstance) -> Tween:
	if config == null or not _unit_sprites.has(unit):
		return null
	_pause_unit_idle(unit)
	# 受击用 position + 纯白 flash shader；先停选中 scale，避免叠脉冲。
	if _drag_select_unit == unit:
		_clear_drag_select_unit()
	else:
		_kill_unit_select_tween(unit)
	var spr := _unit_sprites[unit] as Sprite2D
	var home := _unit_combat_home(unit, spr)
	spr.position = home
	var shake := unit_hit_shake_px()
	var rest := _look().unit_modulate
	spr.modulate = rest
	var mat := _begin_unit_flash(spr)
	# 瞬间完全纯白 → 短停 → 淡回；结束后卸 material，恢复默认 Sprite2D 亮度。
	mat.set_shader_parameter("flash_amount", 1.0)
	var tw := create_tween()
	tw.tween_property(spr, "position", home + Vector2(shake, 0.0), 0.05).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_interval(UNIT_HIT_FLASH_HOLD_SEC)
	tw.tween_property(spr, "position", home, 0.12).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(
		_apply_hit_flash_amount.bind(mat), 1.0, 0.0, UNIT_HIT_FLASH_FADE_SEC
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func() -> void:
		if not is_instance_valid(spr) or not _unit_sprites.has(unit):
			return
		spr.modulate = rest
		_end_unit_flash(spr)
		_snap_unit_to_cell_center(unit)
		if unit.is_alive():
			_ensure_unit_idle(unit)
	)
	return tw


func _begin_unit_flash(spr: Sprite2D) -> ShaderMaterial:
	var mat := spr.material as ShaderMaterial
	if mat == null or mat.shader != HIT_FLASH_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = HIT_FLASH_SHADER
		spr.material = mat
	mat.set_shader_parameter("flash_amount", 0.0)
	return mat


func _end_unit_flash(spr: Sprite2D) -> void:
	if spr == null or not is_instance_valid(spr):
		return
	# 卸掉自定义 material：纯 2D 默认路径，避免 flash=0 时自定义 fragment 在 Compatibility 下偏暗。
	var mat := spr.material as ShaderMaterial
	if mat != null and mat.shader == HIT_FLASH_SHADER:
		spr.material = null


func _apply_hit_flash_amount(amount: float, mat: ShaderMaterial) -> void:
	if mat != null and is_instance_valid(mat):
		mat.set_shader_parameter("flash_amount", amount)


func unit_hit_flash_amount(unit: TacticalUnitInstance) -> float:
	if not _unit_sprites.has(unit):
		return 0.0
	var spr := _unit_sprites[unit] as Sprite2D
	var mat := spr.material as ShaderMaterial
	if mat == null or mat.shader != HIT_FLASH_SHADER:
		return 0.0
	return float(mat.get_shader_parameter("flash_amount"))


func play_unit_death(unit: TacticalUnitInstance) -> void:
	if not _unit_sprites.has(unit):
		return
	_kill_unit_idle(unit)
	if _drag_select_unit == unit:
		_clear_drag_select_unit()
	else:
		_kill_unit_select_tween(unit)
	var spr := _unit_sprites[unit] as Sprite2D
	_end_unit_flash(spr)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", Vector2(0.05, 0.05), 0.32)
	tw.tween_property(spr, "modulate:a", 0.0, 0.32)


func _unit_combat_home(unit: TacticalUnitInstance, spr: Sprite2D) -> Vector2:
	if spr.get_parent() == _units_root:
		return _cell_to_world(unit.cell, config.cell_size)
	_mount_unit_on_tile(unit)
	return Vector2.ZERO


func _snap_unit_to_cell_center(unit: TacticalUnitInstance) -> void:
	if not _unit_sprites.has(unit):
		return
	var spr := _unit_sprites[unit] as Sprite2D
	_mount_unit_on_tile(unit)
	spr.position = Vector2.ZERO
	_place_unit_blob(unit)
	_apply_unit_draw_depth(unit)


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
	var metrics := _texture_content_metrics(tex)
	var content_h: float = metrics.content_h
	var vis := unit.def.visual_scale if unit.def.visual_scale > 0.0 else 1.0
	var s := (unit_h / content_h) * vis if content_h > 0.0 else 1.0
	var base_scale := Vector2(s, s)
	spr.texture = tex
	spr.modulate = _look().unit_modulate if unit.is_alive() else Color(0.4, 0.4, 0.4, 0.5)
	_unit_base_scales[unit] = base_scale
	# 拖牌选中脉冲中勿重置 scale，否则每帧 sync 会掐断 tween。
	if not _unit_select_tweens.has(unit):
		spr.scale = base_scale
	# 节点原点 = 脚点。offset 对齐不透明底边，脚落在格心，身体在脚点上方。
	spr.centered = true
	var base_offset := Vector2(0.0, metrics.offset_y)
	_unit_base_offsets[unit] = base_offset
	if not _unit_idle_tweens.has(unit):
		spr.offset = base_offset
	_ensure_hp_bar(unit)


## 按贴图不透明区域算内容高度与脚点 offset.y（cached）。
func _texture_content_metrics(tex: Texture2D) -> Dictionary:
	if tex == null:
		return {"content_h": 1.0, "offset_y": 0.0}
	if _tex_content_cache.has(tex):
		return _tex_content_cache[tex] as Dictionary
	var tex_h := float(tex.get_height())
	var content_h := tex_h
	var offset_y := -tex_h * 0.5
	var img: Image = tex.get_image()
	if img != null:
		var used: Rect2i = img.get_used_rect()
		if used.size.y > 0:
			content_h = float(used.size.y)
			# centered 时纹理底边在 +tex_h/2；内容底边相对中心再减去顶部空白。
			offset_y = tex_h * 0.5 - float(used.position.y + used.size.y)
	var metrics := {"content_h": content_h, "offset_y": offset_y}
	_tex_content_cache[tex] = metrics
	return metrics


func _kill_unit_idle(unit: TacticalUnitInstance) -> void:
	if not _unit_idle_tweens.has(unit):
		return
	var tw: Tween = _unit_idle_tweens[unit] as Tween
	_unit_idle_tweens.erase(unit)
	if tw != null and is_instance_valid(tw):
		tw.kill()


func _pause_unit_idle(unit: TacticalUnitInstance) -> void:
	_kill_unit_idle(unit)
	if _unit_sprites.has(unit) and _unit_base_offsets.has(unit):
		(_unit_sprites[unit] as Sprite2D).offset = _unit_base_offsets[unit] as Vector2


func _ensure_unit_idle(unit: TacticalUnitInstance) -> void:
	if config == null or not unit.is_alive() or not _unit_sprites.has(unit):
		return
	if _unit_idle_tweens.has(unit):
		var existing: Tween = _unit_idle_tweens[unit] as Tween
		if existing != null and is_instance_valid(existing) and existing.is_running():
			return
	_kill_unit_idle(unit)
	var spr := _unit_sprites[unit] as Sprite2D
	var base: Vector2 = _unit_base_offsets.get(unit, spr.offset) as Vector2
	_unit_base_offsets[unit] = base
	# 各单位从不同相位起漂，避免齐步呼吸；不设 per-loop delay。
	var phase_i := absi(int(hash("%s:%s" % [unit.def.id, unit.faction]))) % 8
	var start_y := base.y - UNIT_IDLE_BOB_PX * (float(phase_i) / 7.0)
	spr.offset = Vector2(base.x, start_y)
	# 绑在单位 Sprite 上：随单位释放；headless 在尚未 enter tree 时也可创建。
	var tw: Tween = spr.create_tween() if spr.is_inside_tree() else create_tween()
	tw.set_loops()
	tw.tween_property(spr, "offset:y", base.y - UNIT_IDLE_BOB_PX, UNIT_IDLE_HALF_SEC).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(spr, "offset:y", base.y, UNIT_IDLE_HALF_SEC).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	_unit_idle_tweens[unit] = tw


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
			_update_burn_badge(unit as TacticalUnitInstance)
	for unit in _unit_blobs:
		var spr := _unit_sprites.get(unit) as Sprite2D
		if spr == null:
			continue
		var blob := _unit_blobs[unit] as Sprite2D
		var parent_s := maxf(absf(spr.scale.x), 0.0001)
		var r := _look().unit_blob_radius * config.cell_size * 2.0
		# 抵消父节点缩放，软影保持格子尺度并留在脚点。
		blob.scale = Vector2((r / 64.0) / parent_s, (r / 64.0) / parent_s * 0.7)
		blob.position = Vector2.ZERO
		blob.visible = spr.modulate.a > BLOB_HIDE_ALPHA


func _ensure_hp_bar(unit: TacticalUnitInstance) -> void:
	var bar: Label
	if _hp_bars.has(unit):
		bar = _hp_bars[unit] as Label
	else:
		bar = Label.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bar.add_theme_font_override("font", UI_FONT)
		bar.add_theme_font_size_override("font_size", 11)
		bar.add_theme_color_override("font_outline_color", Color("0a1018"))
		bar.add_theme_constant_override("outline_size", 3)
		_labels_root.add_child(bar)
		_hp_bars[unit] = bar
	_update_hp_bar(unit)
	_ensure_burn_badge(unit)


func _ensure_burn_badge(unit: TacticalUnitInstance) -> void:
	if _burn_badges.has(unit):
		_update_burn_badge(unit)
		return
	var badge := Label.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_override("font", UI_FONT)
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", BURN_BADGE_COLOR)
	badge.add_theme_color_override("font_outline_color", Color("2a0c04"))
	badge.add_theme_constant_override("outline_size", 4)
	badge.visible = false
	_labels_root.add_child(badge)
	_burn_badges[unit] = badge
	_update_burn_badge(unit)


func _update_hp_bar(unit: TacticalUnitInstance) -> void:
	if not _hp_bars.has(unit) or not _unit_sprites.has(unit):
		return
	var bar := _hp_bars[unit] as Label
	var spr := _unit_sprites[unit] as Sprite2D
	# 常驻：当前/上限血量 + 有效战斗力（含 atk_bonus）；有护甲时附「甲N」。
	if unit.armor > 0:
		bar.text = "%d/%d 攻%d 甲%d" % [
			unit.hp,
			unit.effective_max_hp(),
			unit.effective_attack(),
			unit.armor,
		]
	else:
		bar.text = "%d/%d 攻%d" % [unit.hp, unit.effective_max_hp(), unit.effective_attack()]
	# 节点在脚点；读数放在头顶（整段身高之上）。
	var head_off := Vector2(0.0, -config.unit_world_height * 1.12)
	_position_world_on_label(bar, _unit_world_position(spr) + head_off)
	if unit.hp <= unit.effective_max_hp() / 3:
		bar.modulate = Color("ff6666")
	elif unit.armor > 0:
		bar.modulate = Color("9ad0ff")
	elif unit.atk_bonus > 0:
		bar.modulate = Color("ffe08a")
	else:
		bar.modulate = Color("e8f0ff")


func _update_burn_badge(unit: TacticalUnitInstance) -> void:
	if not _burn_badges.has(unit) or not _unit_sprites.has(unit):
		return
	var badge := _burn_badges[unit] as Label
	if unit.burn_stacks <= 0 or not unit.is_alive():
		badge.visible = false
		return
	badge.visible = true
	# ◆ 作火焰形占位图标 + 层数数字（纯 2D Label，无 Light2D）。
	badge.text = "◆燃%d" % unit.burn_stacks
	var spr := _unit_sprites[unit] as Sprite2D
	var side_off := Vector2(config.unit_world_height * 0.55, -config.unit_world_height * 0.55)
	_position_world_on_label(badge, _unit_world_position(spr) + side_off)
	_clamp_label_in_viewport(badge)


func _position_world_on_label(lbl: Control, world: Vector2) -> void:
	if _camera == null or not _camera.is_inside_tree():
		lbl.position = world
		return
	var canvas := _camera.get_canvas_transform()
	var screen := canvas * world
	lbl.position = screen - lbl.size * 0.5


func _clamp_label_in_viewport(lbl: Control) -> void:
	if lbl == null or _viewport == null:
		return
	var vs := Vector2(_viewport.size)
	if vs.x <= 1.0 or vs.y <= 1.0:
		return
	var pad := 4.0
	var w := maxf(lbl.size.x * absf(lbl.scale.x), 1.0)
	var h := maxf(lbl.size.y * absf(lbl.scale.y), 1.0)
	lbl.position.x = clampf(lbl.position.x, pad, maxf(pad, vs.x - w - pad))
	lbl.position.y = clampf(lbl.position.y, pad, maxf(pad, vs.y - h - pad))


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
	var forest: Node2D = root.get_node_or_null("Forest") as Node2D
	var is_forest := terrain_id == &"forest"
	if forest != null:
		forest.visible = is_forest
		if is_forest:
			_update_forest_geometry(cell)
	root.rotation = 0.0
	root.z_as_relative = false
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
	elif cell == _overlay_drag_hover:
		if _overlay_drag_hover_kind > 0:
			tag = "hv"
		elif _overlay_drag_hover_kind < 0:
			tag = "hx"
		else:
			tag = "h"
	ov.visible = tag != ""
	if tag != "":
		ov.color = OVERLAY_COLORS.get(tag, Color(1, 1, 1, 0.4)) as Color


func _clear_burn_markers() -> void:
	if _burn_pulse_tween != null and is_instance_valid(_burn_pulse_tween):
		_burn_pulse_tween.kill()
	_burn_pulse_tween = null
	for key in _burn_markers.keys():
		var node: Node = _burn_markers[key] as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	_burn_markers.clear()


func _sync_burn_markers() -> void:
	if config == null or _tiles_root == null:
		return
	var keep: Dictionary = {}
	for cell in _overlay_burn.keys():
		if cell is Vector2i:
			keep[cell] = true
			_ensure_burn_marker(cell as Vector2i)
	var stale: Array = []
	for key in _burn_markers.keys():
		if not keep.has(key):
			stale.append(key)
	for key in stale:
		var node: Node = _burn_markers[key] as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
		_burn_markers.erase(key)
	_ensure_burn_pulse()


func _ensure_burn_marker(cell: Vector2i) -> void:
	if _burn_markers.has(cell):
		var existing := _burn_markers[cell] as Node2D
		if existing != null and is_instance_valid(existing):
			existing.position = _cell_to_world(cell, config.cell_size)
			return
	var root := Node2D.new()
	root.name = "Burn_%d_%d" % [cell.x, cell.y]
	root.z_index = BURN_MARKER_Z
	root.position = _cell_to_world(cell, config.cell_size)
	var half := config.cell_size * 0.28
	var glow := Polygon2D.new()
	glow.name = "Glow"
	glow.color = BURN_MARKER_COLOR
	glow.polygon = PackedVector2Array([
		Vector2(0.0, -half * 1.15),
		Vector2(half * 0.85, 0.0),
		Vector2(0.0, half * 0.75),
		Vector2(-half * 0.85, 0.0),
	])
	root.add_child(glow)
	var core := Polygon2D.new()
	core.name = "Core"
	core.color = BURN_MARKER_CORE
	var ch := half * 0.42
	core.polygon = PackedVector2Array([
		Vector2(0.0, -ch * 1.2),
		Vector2(ch * 0.7, 0.05),
		Vector2(0.0, ch * 0.55),
		Vector2(-ch * 0.7, 0.05),
	])
	root.add_child(core)
	_tiles_root.add_child(root)
	_burn_markers[cell] = root


func _ensure_burn_pulse() -> void:
	if _burn_markers.is_empty():
		if _burn_pulse_tween != null and is_instance_valid(_burn_pulse_tween):
			_burn_pulse_tween.kill()
		_burn_pulse_tween = null
		return
	# Headless / 未入树时只留静态标记，不建脉冲 Tween。
	if not is_inside_tree():
		return
	if _burn_pulse_tween != null and is_instance_valid(_burn_pulse_tween) and _burn_pulse_tween.is_running():
		return
	if _burn_pulse_tween != null and is_instance_valid(_burn_pulse_tween):
		_burn_pulse_tween.kill()
	_burn_pulse_tween = create_tween()
	_burn_pulse_tween.set_loops()
	_burn_pulse_tween.tween_method(_apply_burn_pulse_alpha, 0.55, 1.0, BURN_MARKER_PULSE_SEC).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	_burn_pulse_tween.tween_method(_apply_burn_pulse_alpha, 1.0, 0.55, BURN_MARKER_PULSE_SEC).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)


func _apply_burn_pulse_alpha(alpha: float) -> void:
	for key in _burn_markers.keys():
		var node := _burn_markers[key] as Node2D
		if node == null or not is_instance_valid(node):
			continue
		node.modulate = Color(1.0, 1.0, 1.0, alpha)


## 拖牌悬停：cell 为 null 时清空；unit 非空则播选中 scale 脉冲。
## valid_drop：可落己方合法目标=true；悬停单位但不可落=false；空白格传 false 且 unit=null。
func set_card_drag_hover(cell: Variant, unit: TacticalUnitInstance, valid_drop: bool) -> void:
	var prev_hover := _overlay_drag_hover
	if cell is Vector2i:
		_overlay_drag_hover = cell as Vector2i
		if unit != null and unit.is_alive():
			_overlay_drag_hover_kind = 1 if valid_drop else -1
		else:
			_overlay_drag_hover_kind = 0
	else:
		_overlay_drag_hover = Vector2i(-1, -1)
		_overlay_drag_hover_kind = 0
	if prev_hover != _overlay_drag_hover:
		if prev_hover.x >= 0:
			_apply_overlay(prev_hover)
		if _overlay_drag_hover.x >= 0:
			_apply_overlay(_overlay_drag_hover)
	elif _overlay_drag_hover.x >= 0:
		_apply_overlay(_overlay_drag_hover)
	_set_drag_select_unit(unit if unit != null and unit.is_alive() else null, valid_drop)


func clear_card_drag_hover() -> void:
	set_card_drag_hover(null, null, false)


func _set_drag_select_unit(unit: TacticalUnitInstance, valid_drop: bool) -> void:
	if unit == _drag_select_unit:
		if unit == null or valid_drop == _drag_select_valid:
			return
		# 同单位仅在可落态变化时换脉冲幅度。
		_drag_select_valid = valid_drop
		_start_unit_select_tween(unit, valid_drop)
		return
	_clear_drag_select_unit()
	_drag_select_unit = unit
	_drag_select_valid = valid_drop
	if unit == null:
		return
	_start_unit_select_tween(unit, valid_drop)


func _clear_drag_select_unit() -> void:
	if _drag_select_unit == null:
		return
	var u := _drag_select_unit
	_drag_select_unit = null
	_drag_select_valid = false
	_kill_unit_select_tween(u)


func _kill_unit_select_tween(unit: TacticalUnitInstance) -> void:
	if not _unit_select_tweens.has(unit):
		_restore_unit_base_scale(unit)
		return
	var tw: Tween = _unit_select_tweens[unit] as Tween
	_unit_select_tweens.erase(unit)
	if tw != null and is_instance_valid(tw):
		tw.kill()
	_restore_unit_base_scale(unit)


func _restore_unit_base_scale(unit: TacticalUnitInstance) -> void:
	if not _unit_sprites.has(unit):
		return
	var spr := _unit_sprites[unit] as Sprite2D
	if _unit_base_scales.has(unit):
		spr.scale = _unit_base_scales[unit] as Vector2


func _start_unit_select_tween(unit: TacticalUnitInstance, valid_drop: bool) -> void:
	if not _unit_sprites.has(unit):
		return
	_kill_unit_select_tween(unit)
	var spr := _unit_sprites[unit] as Sprite2D
	var base: Vector2 = _unit_base_scales.get(unit, spr.scale) as Vector2
	_unit_base_scales[unit] = base
	var mul := UNIT_SELECT_SCALE_VALID if valid_drop else UNIT_SELECT_SCALE_INVALID
	var peak := base * mul
	spr.scale = base
	var tw: Tween = spr.create_tween() if spr.is_inside_tree() else create_tween()
	tw.set_loops()
	tw.tween_property(spr, "scale", peak, UNIT_SELECT_HALF_SEC).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	tw.tween_property(spr, "scale", base, UNIT_SELECT_HALF_SEC).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	_unit_select_tweens[unit] = tw


func _draw_depth_for_cell(cell: Vector2i) -> int:
	return (cell.x + cell.y) * DRAW_DEPTH_STRIDE


func _unit_world_position(spr: Sprite2D) -> Vector2:
	var parent := spr.get_parent() as Node2D
	if parent == null or parent == _units_root:
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
			spr.reparent(tile, false)
		else:
			tile.add_child(spr)
	spr.position = Vector2.ZERO
	_apply_unit_draw_depth(unit)


func _float_unit_for_world_tween(spr: Sprite2D) -> void:
	if spr.get_parent() == _units_root:
		return
	var world := _unit_world_position(spr)
	spr.reparent(_units_root, false)
	spr.position = world


func _apply_unit_draw_depth(unit: TacticalUnitInstance) -> void:
	var spr := _unit_sprites.get(unit) as Sprite2D
	if spr == null or config == null:
		return
	# 绝对层级：高于全部地块；更靠屏幕下方的单位后画。
	var screen_y := _cell_to_world(unit.cell, config.cell_size).y
	spr.z_as_relative = false
	spr.z_index = UNIT_Z_BASE + int(round(screen_y * 100.0))


func _place_unit_blob(unit: TacticalUnitInstance) -> void:
	if not _unit_blobs.has(unit) or config == null:
		return
	var blob := _unit_blobs[unit] as Sprite2D
	# 软影贴在脚点（节点原点 = 格心），不跟贴图上移。
	blob.position = Vector2.ZERO
	blob.z_as_relative = true
	blob.z_index = -1


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
	## 反投影到地块顶面 y=tile_height（与 `_cell_ground_center` / 绘制一致）。
	## 若按 y=0 解，斜 45° 下会系统性偏移约 tile_height，格边/角点常点到邻格或盘外 null。
	var pitch := deg_to_rad(config.camera_pitch_deg)
	var yaw := deg_to_rad(config.camera_yaw_deg)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var rx := cos(yaw)
	var rz := -sin(yaw)
	var fx := sin(yaw)
	var fz := cos(yaw)
	var h := config.tile_height
	var adj := Vector2(screen.x, screen.y - h * sp)
	var det := rx * (-fz * cp) - rz * (-fx * cp)
	if absf(det) < 1e-8:
		return Vector3(0.0, h, 0.0)
	var gx := (adj.x * (-fz * cp) - adj.y * rz) / det
	var gz := (rx * adj.y - adj.x * (-fx * cp)) / det
	return Vector3(gx, h, gz)


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
	root.z_as_relative = false
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


func _update_forest_geometry(cell: Vector2i) -> void:
	var root: Node2D = _tile_nodes[cell] as Node2D
	var forest: Node2D = root.get_node_or_null("Forest") as Node2D
	if forest == null:
		return
	for ch in forest.get_children():
		ch.queue_free()
	var half := config.cell_size * config.tile_inset * 0.28
	var canopy_corners: Array = []
	for lc in [
		Vector2(0.0, -half),
		Vector2(half * 0.9, half * 0.35),
		Vector2(0.0, half * 0.55),
		Vector2(-half * 0.9, half * 0.35),
	]:
		canopy_corners.append(_cell_ground_corner(cell, lc.x, lc.y))
	var canopy := Polygon2D.new()
	canopy.name = "Canopy"
	canopy.color = Color(0.12, 0.36, 0.18, 0.92)
	canopy.polygon = _project_poly_local(cell, canopy_corners)
	forest.add_child(canopy)
	var trunk_half := config.cell_size * 0.05
	var trunk_corners: Array = []
	for lc2 in [
		Vector2(-trunk_half, half * 0.2),
		Vector2(trunk_half, half * 0.2),
		Vector2(trunk_half, half * 0.75),
		Vector2(-trunk_half, half * 0.75),
	]:
		trunk_corners.append(_cell_ground_corner(cell, lc2.x, lc2.y))
	var trunk := Polygon2D.new()
	trunk.name = "Trunk"
	trunk.color = Color(0.35, 0.22, 0.12, 0.95)
	trunk.polygon = _project_poly_local(cell, _quad_from_first4(trunk_corners))
	forest.add_child(trunk)


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
	var vs := _viewport.size if _viewport != null else Vector2i(393, 852)
	# 按短边适配：竖屏若用高度会过度放大，盘角出屏、点选需狂拖；横屏短边仍是高度，行为与旧版一致。
	var fit := maxf(minf(float(vs.x), float(vs.y)), 1.0)
	var ortho := maxf(config.camera_ortho_size, 0.1)
	var cam_zoom := fit * maxf(_zoom, 0.05) / ortho
	_camera.zoom = Vector2(cam_zoom, cam_zoom)
	_camera.offset = Vector2.ZERO


## _gui_input 收到的事件 position 已是本控件局部坐标；勿再 make_input_local，
## 否则棋盘不在 (0,0)（竖屏 offset_top）时会二次减去偏移，点到别的格。
func _gui_input(event: InputEvent) -> void:
	if config == null or _camera == null:
		return
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_set_zoom(_zoom * mg.factor)
		accept_event()
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
		return
	# 触摸已由 ScreenTouch/Drag 处理；引擎模拟出的鼠标事件再处理会重复点格。
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
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
				_begin_press(mb.position)
			else:
				_end_press(mb.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_continue_press_motion(mm.position)
			accept_event()


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, _effective_zoom_min(), config.camera_zoom_max)
	_clamp_target()
	_apply_camera()


func _pan_by_screen_delta(delta: Vector2) -> void:
	_target += compute_pan_world_delta(delta)
	_clamp_target()
	_apply_camera()


func compute_pan_world_delta(delta: Vector2) -> Vector3:
	## Camera2D.zoom 已把屏幕像素换成世界单位；再除 _zoom 或沿用 0.02 会让竖屏拖拽几乎不动。
	var cam_z := _camera.zoom.y if _camera != null and _camera.zoom.y > 0.0 else 1.0
	var scaled := delta / maxf(cam_z, 0.001) * config.camera_pan_sensitivity
	var yaw := deg_to_rad(config.camera_yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	return -right * scaled.x - forward * scaled.y


## 棋盘四角在斜投影下的半宽/半高（世界 2D）。
func _board_projected_half_extents() -> Vector2:
	if config == null:
		return Vector2.ONE
	var half_x := float(config.grid_width) * config.cell_size * 0.5
	var half_z := float(config.grid_height) * config.cell_size * 0.5
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for x in [-half_x, half_x]:
		for z in [-half_z, half_z]:
			var p := _oblique_project(Vector3(x, config.tile_height, z))
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
	return Vector2(maxf(max_x - min_x, 0.1) * 0.5, maxf(max_y - min_y, 0.1) * 0.5)


## 当前视口刚好装下整盘（含边距）所需的 _zoom；更小 = 更远。
func _zoom_to_fit_board() -> float:
	if config == null:
		return 0.35
	var vs := _viewport.size if _viewport != null else Vector2i(393, 574)
	if vs.x <= 1 or vs.y <= 1:
		return config.camera_zoom_min
	var half := _board_projected_half_extents()
	var pad := config.cell_size * 0.75
	var fit := maxf(minf(float(vs.x), float(vs.y)), 1.0)
	var ortho := maxf(config.camera_ortho_size, 0.1)
	var cam_x := float(vs.x) / maxf(2.0 * (half.x + pad), 0.1)
	var cam_y := float(vs.y) / maxf(2.0 * (half.y + pad), 0.1)
	return (minf(cam_x, cam_y) * ortho) / fit


func _effective_zoom_min() -> float:
	if config == null:
		return 0.35
	# 配置下限与「看全盘」取更小，保证竖屏滚轮/捏合能缩到整张地图。
	return minf(config.camera_zoom_min, _zoom_to_fit_board())


func _handle_screen_touch(st: InputEventScreenTouch) -> void:
	if st.pressed:
		_active_touches[st.index] = st.position
		if _active_touches.size() == 1:
			_touch_drag_index = st.index
			_begin_press(st.position)
		elif _active_touches.size() >= 2:
			_cancel_long_press()
			_dragging = false
			_touch_drag_index = -1
			_pinch_last_distance = _pinch_distance()
	else:
		_active_touches.erase(st.index)
		if st.index == _touch_drag_index:
			_end_press(st.position)
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
			_cancel_long_press()
	accept_event()


func _handle_screen_drag(sd: InputEventScreenDrag) -> void:
	if _active_touches.has(sd.index):
		_active_touches[sd.index] = sd.position
	if _active_touches.size() >= 2:
		_cancel_long_press()
		_apply_pinch_zoom()
		accept_event()
		return
	if not _dragging or sd.index != _touch_drag_index:
		return
	_continue_press_motion(sd.position)
	accept_event()


func _begin_press(local_pos: Vector2) -> void:
	_dragging = true
	_drag_moved = false
	_drag_last = local_pos
	_press_pos = local_pos
	_suppress_click = false
	_press_unit = _unit_under_local(local_pos)
	_deploy_drag_unit = null
	_cancel_long_press()
	if _press_unit != null and _long_press_timer != null:
		_long_press_timer.start()


func _is_deploy_draggable(unit: TacticalUnitInstance) -> bool:
	return (
		_deploy_mode
		and unit != null
		and unit.is_alive()
		and unit.faction == TacticalFactionScript.Id.PLAYER
	)


func _deploy_drop_valid_at(cell: Vector2i) -> bool:
	if not _deploy_valid_cells.has(cell):
		return false
	var occupant := _unit_under_cell(cell)
	if occupant == null or occupant == _deploy_drag_unit:
		return true
	return occupant.faction == TacticalFactionScript.Id.PLAYER


func _unit_under_cell(cell: Vector2i) -> TacticalUnitInstance:
	for key in _unit_sprites.keys():
		var u := key as TacticalUnitInstance
		if u != null and u.is_alive() and u.cell == cell:
			return u
	return null


func _continue_press_motion(local_pos: Vector2) -> void:
	var delta := local_pos - _drag_last
	_drag_last = local_pos
	var dist := _press_pos.distance_to(local_pos)
	if not _drag_moved and dist >= DRAG_THRESHOLD_PX:
		_drag_moved = true
		# 部署：越过阈值后改为拖单位，不再平移镜头。
		if _is_deploy_draggable(_press_unit):
			_deploy_drag_unit = _press_unit
			_cancel_long_press()
			_pause_unit_idle(_deploy_drag_unit)
	if dist >= LONG_PRESS_SLOP_PX:
		_cancel_long_press()
		if _deploy_drag_unit == null:
			_press_unit = null
	if _deploy_drag_unit != null:
		var cell_v: Variant = _pick_cell(local_pos)
		if cell_v == null:
			clear_card_drag_hover()
		else:
			var cell: Vector2i = cell_v
			set_card_drag_hover(cell, _deploy_drag_unit, _deploy_drop_valid_at(cell))
		return
	if _drag_moved and not _info_shown:
		_pan_by_screen_delta(delta)


func _end_press(local_pos: Vector2) -> void:
	_dragging = false
	_cancel_long_press()
	if _info_shown:
		_info_shown = false
		_suppress_click = true
		unit_info_closed.emit()
		_press_unit = null
		_clear_deploy_drag()
		clear_card_drag_hover()
		return
	if _deploy_drag_unit != null:
		var dropped := _deploy_drag_unit
		var cell_v: Variant = _pick_cell(local_pos)
		clear_card_drag_hover()
		_clear_deploy_drag()
		_press_unit = null
		_suppress_click = false
		if cell_v != null:
			unit_deploy_dropped.emit(dropped, cell_v as Vector2i)
		return
	if not _drag_moved and not _suppress_click:
		_handle_click(local_pos)
	_press_unit = null
	_suppress_click = false


func _cancel_long_press() -> void:
	if _long_press_timer != null:
		_long_press_timer.stop()


func _on_long_press_timeout() -> void:
	if _press_unit == null or not _press_unit.is_alive():
		return
	if _drag_moved:
		return
	_info_shown = true
	_suppress_click = true
	unit_long_pressed.emit(_press_unit, unit_head_global_position(_press_unit))


func _unit_under_local(local_pos: Vector2) -> TacticalUnitInstance:
	var cell: Variant = _pick_cell(local_pos)
	if cell == null:
		return null
	var c := cell as Vector2i
	for key in _unit_sprites.keys():
		var u := key as TacticalUnitInstance
		if u != null and u.is_alive() and u.cell == c:
			return u
	return null


## 单位头顶锚点（全局屏幕坐标），供信息卡定位。
func unit_head_global_position(unit: TacticalUnitInstance) -> Vector2:
	if unit == null or not _unit_sprites.has(unit) or _camera == null:
		return get_global_rect().get_center()
	var spr := _unit_sprites[unit] as Sprite2D
	var world := _unit_world_position(spr) + Vector2(0.0, -config.unit_world_height * 1.05)
	var canvas := _camera.get_canvas_transform()
	var vp_pos := canvas * world
	if _viewport_container == null or _viewport == null:
		return get_global_transform_with_canvas() * vp_pos
	var vs := _viewport.size
	var cs := _viewport_container.size
	if vs.x <= 0 or vs.y <= 0 or cs.x <= 0.0 or cs.y <= 0.0:
		return _viewport_container.get_global_transform_with_canvas() * vp_pos
	var local_in_view := Vector2(vp_pos.x * cs.x / float(vs.x), vp_pos.y * cs.y / float(vs.y))
	return _viewport_container.get_global_transform_with_canvas() * local_in_view


func is_unit_info_open() -> bool:
	return _info_shown


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


## 供手牌拖放：把全局屏幕坐标映射到格子（越界返回 null）。
func pick_cell_at_global(global_pos: Vector2) -> Variant:
	return _pick_cell(get_global_transform_with_canvas().affine_inverse() * global_pos)


func _pick_cell(local_pos: Vector2) -> Variant:
	## 2D「射线」：相机逆变换到棋盘世界坐标，再对可见格菱形做点在多边形内测试。
	if _camera == null or config == null or size.y <= 0.0 or size.x <= 0.0 or not _camera.is_inside_tree():
		return null
	if local_pos.x < 0.0 or local_pos.y < 0.0 or local_pos.x > size.x or local_pos.y > size.y:
		return null
	var vp_pos := _to_viewport_pos(local_pos)
	var hit: Vector2 = _camera.get_canvas_transform().affine_inverse() * vp_pos
	return _pick_cell_at_world(hit)


func _pick_cell_at_world(world: Vector2) -> Variant:
	if _tile_nodes.is_empty():
		var ground := _oblique_unproject_ground(world)
		return _world_to_cell(ground)
	# 先用反投影猜一格，命中可视多边形则直接用（快路径）。
	var guess: Variant = _world_to_cell(_oblique_unproject_ground(world))
	if guess is Vector2i and _world_hits_cell_poly(world, guess as Vector2i):
		return guess
	# 否则扫全部可见格：取屏幕纵深最大者（更靠前、与绘制一致）。
	var best: Variant = null
	var best_z := -2147483648
	for cell in _tile_nodes.keys():
		var c: Vector2i = cell as Vector2i
		if not _world_hits_cell_poly(world, c):
			continue
		var z := _draw_depth_for_cell(c)
		if z >= best_z:
			best_z = z
			best = c
	return best


func _world_hits_cell_poly(world: Vector2, cell: Vector2i) -> bool:
	if not _tile_nodes.has(cell):
		return false
	var root: Node2D = _tile_nodes[cell] as Node2D
	var grass: Polygon2D = root.get_node_or_null("Grass") as Polygon2D
	if grass == null or grass.polygon.size() < 3:
		return false
	var poly := PackedVector2Array()
	poly.resize(grass.polygon.size())
	for i in grass.polygon.size():
		poly[i] = root.position + grass.polygon[i]
	return Geometry2D.is_point_in_polygon(world, poly)


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
	## Control 本地像素 → SubViewport 像素（stretch 时按容器与视口比例换算）。
	if _viewport == null or _viewport_container == null:
		return local_pos
	var container_size := _viewport_container.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return local_pos
	var vs := _viewport.size
	if vs.x <= 0 or vs.y <= 0:
		return local_pos
	return Vector2(local_pos.x * float(vs.x) / container_size.x, local_pos.y * float(vs.y) / container_size.y)


func _clamp_target() -> void:
	var cell_size := config.cell_size
	var half_w := float(config.grid_width) * cell_size * 0.5
	var half_h := float(config.grid_height) * cell_size * 0.5
	var pad := cell_size * 1.5
	_target.x = clampf(_target.x, -half_w - pad, half_w + pad)
	_target.z = clampf(_target.z, -half_h - pad, half_h + pad)
	_target.y = 0.0