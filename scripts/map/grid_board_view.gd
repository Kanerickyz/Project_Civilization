class_name GridBoardView
extends Control
## 2D 方格盘（斜 45° 正交投影）：Polygon2D 格块 + Sprite2D 单位；Camera2D 拖拽/滚轮。


signal cell_clicked(cell: Vector2i)
## 指针悬停格变化（瞄准预览用）；离开棋盘时 cell 为 null。
signal cell_hovered(cell: Variant)
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
const TacticalEnemyAiScript := preload("res://scripts/units/tactical_enemy_ai.gd")
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
	## 非通用技拖牌：可释放/技能规则格（金）。
	"sk": Color(0.95, 0.78, 0.35, 0.48),
	## 点燃地块（可与选中/移动/攻击叠显：独立 marker，本色仅作参考）。
	"b": Color(1.0, 0.42, 0.12, 0.38),
	## 狼骑下一意图：路径格 / 攻击目标格（低于选中/红攻/绿移）。
	"ip": Color(0.55, 0.88, 1.0, 0.38),
	"it": Color(1.0, 0.62, 0.28, 0.52),
}
const SKILL_ARROW_VALID := Color(0.98, 0.86, 0.42, 0.95)
const SKILL_ARROW_INVALID := Color(0.82, 0.38, 0.4, 0.75)
const SKILL_ARROW_SEGMENTS := 18
const INTENT_GHOST_ALPHA := 0.42
const INTENT_PATH_LINE_COLOR := Color(0.55, 0.9, 1.0, 0.85)
const INTENT_ATK_LINE_COLOR := Color(1.0, 0.45, 0.32, 0.9)
const INTENT_HINT_COLOR := Color(0.95, 0.98, 0.7, 1.0)
const BURN_MARKER_COLOR := Color(1.0, 0.45, 0.1, 0.72)
const BURN_MARKER_CORE := Color(1.0, 0.85, 0.35, 0.9)
const BURN_BADGE_COLOR := Color("ff7a2e")
const FRENZY_BADGE_COLOR := Color("e84b6a")
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
var _overlay_intent_path: Dictionary = {} # Vector2i -> true
var _overlay_intent_target: Dictionary = {} # Vector2i -> true
## 拖移动卡预览可达（与正式瞄准绿格同色，可并存）。
var _overlay_preview_move: Dictionary = {} # Vector2i -> true
## 拖牌悬停当前格；(-1,-1) 表示无。
var _overlay_drag_hover: Vector2i = Vector2i(-1, -1)
## 0=空白/中性，1=可落单位，-1=不可落单位。
var _overlay_drag_hover_kind: int = 0
## 非通用技拖牌：可释放格高亮。
var _overlay_skill_release: Dictionary = {} # Vector2i -> true
## STS 风格曲线箭头：施法格 → 悬停释放格。
var _skill_aim_arrow: Node2D = null
## 点选状态机敌方：下回合意图虚影（路径线 / 攻击线 / 落点半透明精灵 / 回血加攻召唤提示）。
var _intent_preview_ghost: Sprite2D = null
var _intent_preview_line: Line2D = null
var _intent_preview_hint: Control = null
var _intent_preview_unit: TacticalUnitInstance = null

var _last_unit_cells: Dictionary = {}
var _unit_move_tweens: Dictionary = {} # TacticalUnitInstance -> Tween
var _last_move_tween_sec: float = UNIT_MOVE_HOP_SEC
var _hp_bars: Dictionary = {} # TacticalUnitInstance -> Control（数字 + 分段血条）
var _burn_badges: Dictionary = {} # TacticalUnitInstance -> Control（色菱形 + 燃N）
var _frenzy_badges: Dictionary = {} # TacticalUnitInstance -> Control（色菱形 + 狂N）
var _intent_icons: Dictionary = {} # TacticalUnitInstance -> Control（狼骑下一意图角标）
var _burn_markers: Dictionary = {} # Vector2i -> Node2D（点燃地块标记）
var _overlay_burn: Dictionary = {} # Vector2i -> true
var _burn_pulse_tween: Tween
var _unit_blobs: Dictionary = {} # TacticalUnitInstance -> Sprite2D
var _blob_texture: Texture2D
## 拖牌/瞄准链路预览：unit -> {hp,max_hp,armor,hp_delta,armor_delta}
var _action_preview_deltas: Dictionary = {}
var _action_preview_chain: Control = null
var _pointer_hover_cell: Vector2i = Vector2i(-999, -999)
const HP_SEG_MAX_PIP := 12
const HP_SEG_W := 7.0
const HP_SEG_H := 6.0
const HP_SEG_GAP := 1.0
const HP_FILL := Color("3dd68c")
const HP_EMPTY := Color("2a3340")
const HP_PREVIEW_LOSS := Color("ff5a5a")
const HP_PREVIEW_GAIN := Color("7dff9a")
const ARMOR_FILL := Color("6eb6ff")
const CHAIN_BG := Color(0.08, 0.1, 0.14, 0.88)
## 待机浮动只改 offset，不碰 position，避免挡移动/冲刺/受击 Tween 与格子点选。
var _unit_idle_tweens: Dictionary = {} # TacticalUnitInstance -> Tween
var _unit_base_offsets: Dictionary = {} # TacticalUnitInstance -> Vector2
## 拖牌悬停选中只改 scale，不碰 offset/position/modulate（避 idle bob / hit flash）。
var _unit_select_tweens: Dictionary = {} # TacticalUnitInstance -> Tween
var _unit_base_scales: Dictionary = {} # TacticalUnitInstance -> Vector2
## 被动触发：单位晃动/弹出/高亮（小丑牌式），与选中脉冲互斥。
var _unit_passive_tweens: Dictionary = {} # TacticalUnitInstance -> Tween
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
const STEALTH_SPRITE_ALPHA := 0.42

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


## 部署落位成功：对齐逻辑格并跳过 hop（拖放已跟手到落点）。
func accept_deploy_placement(unit: TacticalUnitInstance, previous_cell: Vector2i) -> void:
	if unit == null:
		return
	_last_unit_cells[unit] = unit.cell
	var other := _unit_under_cell(previous_cell)
	if other != null and other != unit:
		_last_unit_cells[other] = other.cell
		_kill_unit_move_tween(other)
		_snap_unit_to_cell_center(other)
		if other.is_alive():
			_ensure_unit_idle(other)
	_kill_unit_move_tween(unit)
	_snap_unit_to_cell_center(unit)
	if unit.is_alive():
		_ensure_unit_idle(unit)


## 部署落位失败 / 越界：角色弹回原格。
func cancel_deploy_drag_visual(unit: TacticalUnitInstance) -> void:
	if unit == null or not _unit_sprites.has(unit):
		return
	_kill_unit_move_tween(unit)
	_snap_unit_to_cell_center(unit)
	if unit.is_alive():
		_ensure_unit_idle(unit)


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
		_update_tile_geometry(cell)
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
	# Control 层先铺 BoardLook 纯色：Web/竖屏下 stretch 同步前也不透出异色块。
	_chrome = ColorRect.new()
	_chrome.name = "BoardChrome"
	_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chrome)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# stretch=true：容器负责把 SubViewport 拉满；勿手改 size（引擎会忽略并留下未铺满色块）。
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
	_overlay_skill_release.clear()
	_skill_aim_arrow = null
	_clear_deploy_drag()
	for key in _unit_sprites.keys():
		_kill_unit_idle(key as TacticalUnitInstance)
		_kill_unit_select_tween(key as TacticalUnitInstance)
		_kill_unit_passive_tween(key as TacticalUnitInstance)
		(_unit_sprites[key] as Node).queue_free()
	_unit_passive_tweens.clear()
	for child in _tiles_root.get_children():
		child.queue_free()
	for child in _units_root.get_children():
		child.queue_free()
	_tile_nodes.clear()
	_overlay_nodes.clear()
	_unit_sprites.clear()
	_unit_blobs.clear()
	for key in _hp_bars.keys():
		var hp_root: Control = _hp_bars[key] as Control
		if hp_root != null and is_instance_valid(hp_root):
			hp_root.queue_free()
	_hp_bars.clear()
	clear_action_preview()
	for key in _burn_badges.keys():
		var burn_root: Control = _burn_badges[key] as Control
		if burn_root != null and is_instance_valid(burn_root):
			burn_root.queue_free()
	_burn_badges.clear()
	for key in _frenzy_badges.keys():
		var frenzy_root: Control = _frenzy_badges[key] as Control
		if frenzy_root != null and is_instance_valid(frenzy_root):
			frenzy_root.queue_free()
	_frenzy_badges.clear()
	for key in _intent_icons.keys():
		var intent_icon: Control = _intent_icons[key] as Control
		if intent_icon != null and is_instance_valid(intent_icon):
			intent_icon.queue_free()
	_intent_icons.clear()
	_clear_intent_preview()
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
	ignited_cells: Array = [],
	intent_preview: Dictionary = {},
	intent_unit: TacticalUnitInstance = null
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
	_sync_intent_preview(intent_preview, intent_unit)
	for cell in _overlay_nodes.keys():
		_apply_overlay(cell)


func _sync_unit_position(unit: TacticalUnitInstance) -> void:
	var spr := _unit_sprites[unit] as Sprite2D
	# 逻辑格已变且正在播移动 Tween 时，勿再 sync（否则会 kill tween 并瞬移到终点）。
	if _unit_move_tweens.has(unit):
		_update_hp_bar(unit)
		_update_burn_badge(unit)
		_update_intent_icon(unit)
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
	_update_burn_badge(unit)
	_update_intent_icon(unit)


## 受击/冲刺位移相对 cell_size 的上限（世界单位；旧 +4.0 在 cell_size=1 时飞出数格）。
const UNIT_HIT_SHAKE_FRAC := 0.08
const UNIT_ATTACK_LUNGE_FRAC := 0.28
## 受击纯白闪：仅命中瞬间挂 flash shader；平时 material=null，走默认 Sprite2D 着色（避免常驻 shader 压暗）。
const UNIT_HIT_FLASH_HOLD_SEC := 0.08
const UNIT_HIT_FLASH_FADE_SEC := 0.22
const DAMAGE_POPUP_FONT_SIZE := 28
const DAMAGE_POPUP_LIFT_PX := 56.0
## 被动触发（参考小丑牌）：单位抖、弹出 + 更冲的飘字（无金色高亮）。
const PASSIVE_TRIGGER_SHAKE_FRAC := 0.07
const PASSIVE_TRIGGER_SCALE := 1.22
const PASSIVE_POPUP_FONT_SIZE := 32
const PASSIVE_POPUP_LIFT_PX := 64.0
## 同格飘字串行：相邻两条（伤害/加攻/加血等）开始弹出间隔。
const FLOAT_QUEUE_INTERVAL_SEC := 0.4
## cell_key -> Array[Dictionary] 待播飘字；同格不并行叠。
var _float_queues: Dictionary = {}
## cell_key -> true 时该格正在播或等待间隔，禁止立刻弹出下一条。
var _float_queue_busy: Dictionary = {}


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
	var path := _resolve_move_path(from_cell, to_cell, unit)
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


func _resolve_move_path(
	from_cell: Vector2i, to_cell: Vector2i, mover: TacticalUnitInstance = null
) -> Array[Vector2i]:
	return GridPathfindingScript.shortest_path(
		from_cell,
		to_cell,
		func(cell: Vector2i) -> bool:
			return _view_cell_passable_for_move(cell, mover)
	)


func _view_cell_passable(cell: Vector2i) -> bool:
	if config == null:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= config.grid_width or cell.y >= config.grid_height:
		return false
	var tid := terrain_id_at(cell)
	var cat := _get_catalog()
	return cat.is_present(tid) and cat.is_passable(tid)


## 表现层移动格序：与逻辑一致，绕开敌方占格；友方中间可穿过。
func _view_cell_passable_for_move(cell: Vector2i, mover: TacticalUnitInstance) -> bool:
	if not _view_cell_passable(cell):
		return false
	if mover == null:
		return true
	for key in _unit_sprites.keys():
		var other: TacticalUnitInstance = key as TacticalUnitInstance
		if other == null or other == mover or not other.is_alive():
			continue
		if other.cell != cell:
			continue
		if other.faction != mover.faction:
			return false
	return true


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
	_kill_unit_passive_tween(unit)
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
		var bar: Control = _hp_bars[unit] as Control
		bar.queue_free()
		_hp_bars.erase(unit)
	_action_preview_deltas.erase(unit)
	if _burn_badges.has(unit):
		var badge: Control = _burn_badges[unit] as Control
		badge.queue_free()
		_burn_badges.erase(unit)
	if _frenzy_badges.has(unit):
		var frenzy_badge: Control = _frenzy_badges[unit] as Control
		frenzy_badge.queue_free()
		_frenzy_badges.erase(unit)
	if _intent_icons.has(unit):
		var intent_icon: Control = _intent_icons[unit] as Control
		intent_icon.queue_free()
		_intent_icons.erase(unit)
	_last_unit_cells.erase(unit)


func play_damage_popup(cell: Vector2i, amount: int) -> void:
	play_float_text(cell, "-%d" % maxi(0, amount), Color("ff5533"))


## 伤害等通用飘字：入同格串行队列（间隔 FLOAT_QUEUE_INTERVAL_SEC）。
## stack_index 保留兼容，已忽略（同格不再并行错开叠字）。
func play_float_text(
	cell: Vector2i, text: String, color: Color = Color("ff5533"), _stack_index: int = 0
) -> void:
	_enqueue_float_label(
		{
			"cell": cell,
			"text": text,
			"color": color,
			"font_size": DAMAGE_POPUP_FONT_SIZE,
			"lift_px": DAMAGE_POPUP_LIFT_PX,
			"start_scale": Vector2(0.55, 0.55),
			"peak_scale": Vector2(1.12, 1.12),
			"pop_sec": 0.14,
			"lift_sec": 0.55,
			"fade_sec": 0.38,
			"fade_delay": 0.2,
			"outline_size": 5,
		}
	)


## 被动数值/能力名飘字：更强 BACK 弹出；与伤害共用同格队列。
func play_passive_float_text(
	cell: Vector2i, text: String, color: Color = Color("ffe08a"), _stack_index: int = 0
) -> void:
	_enqueue_float_label(
		{
			"cell": cell,
			"text": text,
			"color": color,
			"font_size": PASSIVE_POPUP_FONT_SIZE,
			"lift_px": PASSIVE_POPUP_LIFT_PX,
			"start_scale": Vector2(0.28, 0.28),
			"peak_scale": Vector2(1.32, 1.32),
			"pop_sec": 0.18,
			"lift_sec": 0.62,
			"fade_sec": 0.42,
			"fade_delay": 0.24,
			"outline_size": 6,
		}
	)


func _float_cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _enqueue_float_label(item: Dictionary) -> void:
	if config == null:
		return
	var text := str(item.get("text", ""))
	if text.is_empty():
		return
	var cell: Vector2i = item.get("cell", Vector2i(-999, -999)) as Vector2i
	var key := _float_cell_key(cell)
	if not _float_queues.has(key):
		_float_queues[key] = []
	(_float_queues[key] as Array).append(item)
	_pump_float_queue(cell)


func _pump_float_queue(cell: Vector2i) -> void:
	var key := _float_cell_key(cell)
	if bool(_float_queue_busy.get(key, false)):
		return
	if not _float_queues.has(key):
		return
	var q: Array = _float_queues[key] as Array
	if q.is_empty():
		_float_queues.erase(key)
		return
	_float_queue_busy[key] = true
	var item: Dictionary = q.pop_front() as Dictionary
	if q.is_empty():
		_float_queues.erase(key)
	_spawn_float_label(item)
	# 相邻两条间隔 0.4s（从本条开始算起），再播下一条。
	var tree := get_tree()
	if tree == null:
		_float_queue_busy.erase(key)
		return
	tree.create_timer(FLOAT_QUEUE_INTERVAL_SEC, true, false, true).timeout.connect(
		func() -> void:
			_float_queue_busy.erase(key)
			_pump_float_queue(cell)
	)


## 战斗表现是否仍在播：飘字队列/在飞飘字、被动抖动、位移 Tween。
## 勿把常驻血攻 Label（同挂 _labels_root）当成在播，否则结束行动会空等超时。
func is_combat_presentation_busy() -> bool:
	if not _float_queues.is_empty():
		return true
	for busy_v in _float_queue_busy.values():
		if bool(busy_v):
			return true
	if _labels_root != null:
		for child in _labels_root.get_children():
			if child is Label and bool(child.get_meta("combat_float", false)):
				return true
	if not _unit_passive_tweens.is_empty():
		return true
	if not _unit_move_tweens.is_empty():
		return true
	return false


func _spawn_float_label(item: Dictionary) -> void:
	if config == null or _labels_root == null:
		return
	var cell: Vector2i = item.get("cell", Vector2i(-999, -999)) as Vector2i
	var text := str(item.get("text", ""))
	if text.is_empty():
		return
	var color: Color = item.get("color", Color("ff5533")) as Color
	var font_size := int(item.get("font_size", DAMAGE_POPUP_FONT_SIZE))
	var lift_px := float(item.get("lift_px", DAMAGE_POPUP_LIFT_PX))
	var start_scale: Vector2 = item.get("start_scale", Vector2(0.55, 0.55)) as Vector2
	var peak_scale: Vector2 = item.get("peak_scale", Vector2(1.12, 1.12)) as Vector2
	var pop_sec := float(item.get("pop_sec", 0.14))
	var lift_sec := float(item.get("lift_sec", 0.55))
	var fade_sec := float(item.get("fade_sec", 0.38))
	var fade_delay := float(item.get("fade_delay", 0.2))
	var outline_size := int(item.get("outline_size", 5))
	# 与常驻 HP 读数同一套世界坐标（格心投影 + 头顶偏移），勿再抬 3D Y / 混像素。
	var world := _cell_to_world(cell, config.cell_size)
	var head := Vector2(0.0, -config.unit_world_height * 1.35)
	var lbl := Label.new()
	lbl.set_meta("combat_float", true)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = text
	lbl.add_theme_font_override("font", UI_FONT)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color("1a0a08"))
	lbl.add_theme_constant_override("outline_size", outline_size)
	lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)
	lbl.scale = start_scale
	_labels_root.add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size * 0.5
	_position_world_on_label(lbl, world + head)
	_clamp_label_in_viewport(lbl)
	var start_pos := lbl.position
	lbl.position = start_pos
	var tw := create_tween()
	tw.set_parallel(true)
	# 上浮在屏幕空间（Control.position），不再经 world→screen。
	tw.tween_property(lbl, "position", start_pos + Vector2(0.0, -lift_px), lift_sec).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", peak_scale, pop_sec).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(lbl, "modulate:a", 0.0, fade_sec).set_delay(fade_delay)
	tw.finished.connect(lbl.queue_free)


## 被动触发单位：左右连抖 + 弹出缩放（无金色高亮/描边）。
func play_passive_trigger(unit: TacticalUnitInstance) -> Tween:
	if config == null or unit == null or not _unit_sprites.has(unit):
		return null
	_pause_unit_idle(unit)
	if _drag_select_unit == unit:
		_clear_drag_select_unit()
	else:
		_kill_unit_select_tween(unit)
	_kill_unit_passive_tween(unit)
	var spr := _unit_sprites[unit] as Sprite2D
	var home := _unit_combat_home(unit, spr)
	spr.position = home
	var base_scale: Vector2 = _unit_base_scales.get(unit, spr.scale) as Vector2
	_unit_base_scales[unit] = base_scale
	spr.scale = base_scale
	var rest := _look().unit_modulate
	if unit.is_stealthed():
		rest.a = STEALTH_SPRITE_ALPHA
	spr.modulate = rest
	var shake := config.cell_size * PASSIVE_TRIGGER_SHAKE_FRAC
	var peak := base_scale * PASSIVE_TRIGGER_SCALE
	var tw := create_tween()
	# 弹出与首拍晃动并行；随后连抖回位（无 modulate 金染）。
	tw.tween_property(spr, "position", home + Vector2(shake, 0.0), 0.04).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(spr, "scale", peak, 0.12).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(spr, "position", home + Vector2(-shake, 0.0), 0.04).set_trans(Tween.TRANS_SINE)
	tw.tween_property(spr, "position", home + Vector2(shake * 0.65, 0.0), 0.04).set_trans(
		Tween.TRANS_SINE
	)
	tw.tween_property(spr, "position", home, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(spr, "scale", base_scale, 0.18).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	_unit_passive_tweens[unit] = tw
	tw.finished.connect(
		func() -> void:
			if _unit_passive_tweens.get(unit) == tw:
				_unit_passive_tweens.erase(unit)
			if not is_instance_valid(spr) or not _unit_sprites.has(unit):
				return
			spr.position = _unit_combat_home(unit, spr)
			_restore_unit_base_scale(unit)
			spr.modulate = rest
			_ensure_unit_idle(unit)
	)
	return tw


func _kill_unit_passive_tween(unit: TacticalUnitInstance) -> void:
	if not _unit_passive_tweens.has(unit):
		return
	var tw: Tween = _unit_passive_tweens[unit] as Tween
	_unit_passive_tweens.erase(unit)
	if tw != null and is_instance_valid(tw):
		tw.kill()


func play_unit_hit(unit: TacticalUnitInstance) -> Tween:
	if config == null or not _unit_sprites.has(unit):
		return null
	_pause_unit_idle(unit)
	# 受击用 position + 纯白 flash shader；先停选中/被动 scale，避免叠脉冲。
	if _drag_select_unit == unit:
		_clear_drag_select_unit()
	else:
		_kill_unit_select_tween(unit)
	_kill_unit_passive_tween(unit)
	var spr := _unit_sprites[unit] as Sprite2D
	var home := _unit_combat_home(unit, spr)
	spr.position = home
	var shake := unit_hit_shake_px()
	var rest := _look().unit_modulate
	# 受伤后隐身已破；若仍隐身则保持半透明。
	if unit.is_stealthed():
		rest.a = STEALTH_SPRITE_ALPHA
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
	var base_mod := _look().unit_modulate if unit.is_alive() else Color(0.4, 0.4, 0.4, 0.5)
	if unit.is_alive() and unit.is_stealthed():
		base_mod.a = STEALTH_SPRITE_ALPHA
	spr.modulate = base_mod
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
			_update_frenzy_badge(unit as TacticalUnitInstance)
			_update_intent_icon(unit as TacticalUnitInstance)
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
	var root: Control
	if _hp_bars.has(unit):
		root = _hp_bars[unit] as Control
	else:
		root = Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.name = "HpBar"
		var text := Label.new()
		text.name = "Text"
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.add_theme_color_override("font_outline_color", Color("0a1018"))
		text.add_theme_constant_override("outline_size", 3)
		root.add_child(text)
		var segs := HBoxContainer.new()
		segs.name = "Segments"
		segs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segs.add_theme_constant_override("separation", int(HP_SEG_GAP))
		root.add_child(segs)
		var armor_row := HBoxContainer.new()
		armor_row.name = "ArmorSegments"
		armor_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		armor_row.add_theme_constant_override("separation", int(HP_SEG_GAP))
		root.add_child(armor_row)
		_labels_root.add_child(root)
		_hp_bars[unit] = root
	_update_hp_bar(unit)
	_ensure_burn_badge(unit)
	_ensure_frenzy_badge(unit)
	_ensure_intent_icon(unit)


func _ensure_burn_badge(unit: TacticalUnitInstance) -> void:
	if _burn_badges.has(unit):
		_update_burn_badge(unit)
		return
	# Web 无系统字体：◆ 不在 Noto/Droid；与意图角标同构——旋转方块菱形 + 中文 Label。
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	var gem := ColorRect.new()
	gem.name = "Gem"
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.size = Vector2(8, 8)
	gem.pivot_offset = Vector2(4, 4)
	gem.rotation_degrees = 45.0
	gem.color = BURN_BADGE_COLOR
	root.add_child(gem)
	var text := Label.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_ui_label_font(text, 12)
	text.add_theme_color_override("font_color", BURN_BADGE_COLOR)
	text.add_theme_color_override("font_outline_color", Color("2a0c04"))
	text.add_theme_constant_override("outline_size", 4)
	root.add_child(text)
	_labels_root.add_child(root)
	_burn_badges[unit] = root
	_update_burn_badge(unit)


func _apply_ui_label_font(lbl: Label, font_size: int) -> void:
	# 血攻/燃烧/意图等世界 Label 必须显式挂 ui_font；勿依赖 Theme 默认或系统回退。
	lbl.add_theme_font_override("font", UI_FONT)
	lbl.add_theme_font_size_override("font_size", font_size)


func _update_hp_bar(unit: TacticalUnitInstance) -> void:
	if not _hp_bars.has(unit) or not _unit_sprites.has(unit):
		return
	var root := _hp_bars[unit] as Control
	var text := root.get_node("Text") as Label
	var segs := root.get_node("Segments") as HBoxContainer
	var armor_row := root.get_node("ArmorSegments") as HBoxContainer
	_apply_ui_label_font(text, 11)
	var spr := _unit_sprites[unit] as Sprite2D
	var cur_hp := unit.hp
	var max_hp := maxi(1, unit.effective_max_hp())
	var armor_now := unit.armor
	var preview: Dictionary = _action_preview_deltas.get(unit, {}) as Dictionary
	var preview_hp := cur_hp
	var preview_max := max_hp
	var preview_armor := armor_now
	var has_preview := not preview.is_empty()
	if has_preview:
		preview_hp = int(preview.get("hp", cur_hp))
		preview_max = maxi(1, int(preview.get("max_hp", max_hp)))
		preview_armor = int(preview.get("armor", armor_now))
	# 数字：当前/上限；预览时显示将变成的血量。
	var show_hp := preview_hp if has_preview else cur_hp
	var show_max := preview_max if has_preview else max_hp
	var bits: PackedStringArray = [
		"%d/%d" % [show_hp, show_max],
		"攻%d" % unit.effective_attack(),
	]
	var show_armor := preview_armor if has_preview else armor_now
	if show_armor > 0:
		bits.append("甲%d" % show_armor)
	if unit.is_stealthed():
		bits.append("隐")
	text.text = " ".join(bits)
	text.reset_size()
	if has_preview and int(preview.get("hp_delta", 0)) < 0:
		text.add_theme_color_override("font_color", HP_PREVIEW_LOSS)
	elif has_preview and int(preview.get("hp_delta", 0)) > 0:
		text.add_theme_color_override("font_color", HP_PREVIEW_GAIN)
	elif cur_hp <= max_hp / 3:
		text.add_theme_color_override("font_color", Color("ff6666"))
	elif unit.is_stealthed():
		text.add_theme_color_override("font_color", Color("b8c4d8"))
	elif armor_now > 0:
		text.add_theme_color_override("font_color", Color("9ad0ff"))
	elif unit.atk_bonus > 0:
		text.add_theme_color_override("font_color", Color("ffe08a"))
	else:
		text.add_theme_color_override("font_color", Color("e8f0ff"))
	_rebuild_hp_segments(segs, cur_hp, max_hp, preview_hp if has_preview else -1)
	_rebuild_armor_segments(armor_row, show_armor)
	var seg_w := segs.get_combined_minimum_size().x
	var armor_w := armor_row.get_combined_minimum_size().x if armor_row.visible else 0.0
	var width := maxf(text.size.x, maxf(seg_w, armor_w))
	var height := text.size.y + HP_SEG_H + 2.0
	if armor_row.visible:
		height += HP_SEG_H + 1.0
	root.size = Vector2(width, height)
	text.position = Vector2((width - text.size.x) * 0.5, 0.0)
	segs.position = Vector2((width - seg_w) * 0.5, text.size.y + 1.0)
	if armor_row.visible:
		armor_row.position = Vector2(
			(width - armor_w) * 0.5, text.size.y + HP_SEG_H + 2.0
		)
	var head_off := Vector2(0.0, -config.unit_world_height * 1.18)
	_position_world_on_label(root, _unit_world_position(spr) + head_off)


func _rebuild_hp_segments(
	row: HBoxContainer, cur_hp: int, max_hp: int, preview_hp: int = -1
) -> void:
	while row.get_child_count() > 0:
		var ch := row.get_child(0)
		row.remove_child(ch)
		ch.queue_free()
	var pip_count := mini(maxi(1, max_hp), HP_SEG_MAX_PIP)
	var scale := float(max_hp) / float(pip_count)
	for i in range(pip_count):
		var pip := ColorRect.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.custom_minimum_size = Vector2(HP_SEG_W, HP_SEG_H)
		# 每段覆盖的血量区间（向上取整边界）。
		var lo := int(floor(float(i) * scale))
		var hi := int(ceil(float(i + 1) * scale))
		var filled_now := cur_hp > lo
		var filled_preview := preview_hp < 0 or preview_hp > lo
		if preview_hp >= 0 and filled_now and not filled_preview:
			pip.color = HP_PREVIEW_LOSS
		elif preview_hp >= 0 and not filled_now and filled_preview:
			pip.color = HP_PREVIEW_GAIN
		elif filled_now:
			pip.color = HP_FILL
		else:
			pip.color = HP_EMPTY
		# 高血上限时用透明度暗示聚合段。
		if max_hp > HP_SEG_MAX_PIP and hi - lo > 1:
			pip.modulate.a = 0.92
		row.add_child(pip)


func _rebuild_armor_segments(row: HBoxContainer, armor: int) -> void:
	while row.get_child_count() > 0:
		var ch := row.get_child(0)
		row.remove_child(ch)
		ch.queue_free()
	if armor <= 0:
		row.visible = false
		return
	row.visible = true
	var n := mini(armor, HP_SEG_MAX_PIP)
	for _i in range(n):
		var pip := ColorRect.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.custom_minimum_size = Vector2(HP_SEG_W, HP_SEG_H)
		pip.color = ARMOR_FILL
		row.add_child(pip)


## 拖牌/瞄准伤害链路预览：unit_deltas 键为单位；chain_text 显示整条步骤。
func set_action_preview(preview: Dictionary) -> void:
	_action_preview_deltas.clear()
	if preview == null or preview.is_empty() or not bool(preview.get("ok", false)):
		_clear_action_preview_chain()
		for u in _hp_bars.keys():
			_update_hp_bar(u as TacticalUnitInstance)
		return
	var deltas: Dictionary = preview.get("unit_deltas", {}) as Dictionary
	for key in deltas.keys():
		if key is TacticalUnitInstance:
			_action_preview_deltas[key] = deltas[key]
	for u in _hp_bars.keys():
		_update_hp_bar(u as TacticalUnitInstance)
	_show_action_preview_chain(
		str(preview.get("chain_text", "")),
		preview.get("hover_cell", Vector2i(-1, -1))
	)


## GUI：强制展示一条预览（截图用）。
func capture_set_action_preview(preview: Dictionary) -> void:
	set_action_preview(preview)


func clear_action_preview() -> void:
	if (
		_action_preview_deltas.is_empty()
		and _action_preview_chain == null
		and _overlay_preview_move.is_empty()
	):
		return
	_action_preview_deltas.clear()
	_overlay_preview_move.clear()
	_clear_action_preview_chain()
	for u in _hp_bars.keys():
		_update_hp_bar(u as TacticalUnitInstance)
	for cell in _overlay_nodes.keys():
		_apply_overlay(cell as Vector2i)


## 拖移动卡到单位时临时叠绿可达格（不改写正式瞄准 overlay）。
func set_preview_move_cells(cells: Array) -> void:
	var prev := _overlay_preview_move.duplicate()
	_overlay_preview_move.clear()
	for c in cells:
		if c is Vector2i:
			_overlay_preview_move[c as Vector2i] = true
	for cell in prev.keys():
		_apply_overlay(cell as Vector2i)
	for cell in _overlay_preview_move.keys():
		_apply_overlay(cell as Vector2i)


func _clear_action_preview_chain() -> void:
	if _action_preview_chain != null and is_instance_valid(_action_preview_chain):
		_action_preview_chain.queue_free()
	_action_preview_chain = null


func _show_action_preview_chain(chain_text: String, hover_cell: Variant) -> void:
	_clear_action_preview_chain()
	if chain_text.is_empty() or _labels_root == null or config == null:
		return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.name = "ActionPreviewChain"
	var sb := StyleBoxFlat.new()
	sb.bg_color = CHAIN_BG
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(160, 0)
	_apply_ui_label_font(lbl, 12)
	lbl.add_theme_color_override("font_color", Color("f2f6ff"))
	lbl.add_theme_color_override("font_outline_color", Color("0a1018"))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.text = chain_text
	panel.add_child(lbl)
	_labels_root.add_child(panel)
	_action_preview_chain = panel
	lbl.reset_size()
	panel.reset_size()
	var world := Vector2.ZERO
	if hover_cell is Vector2i and (hover_cell as Vector2i).x >= 0:
		world = _cell_to_world(hover_cell as Vector2i, config.cell_size)
		world += Vector2(0.0, -config.unit_world_height * 1.75)
	else:
		world = _target_to_label_anchor()
	_position_world_on_label(panel, world)
	_clamp_label_in_viewport(panel)


func _target_to_label_anchor() -> Vector2:
	if config == null:
		return Vector2.ZERO
	return _cell_to_world(
		Vector2i(config.grid_width / 2, config.grid_height / 2), config.cell_size
	)


func _update_burn_badge(unit: TacticalUnitInstance) -> void:
	if not _burn_badges.has(unit) or not _unit_sprites.has(unit):
		return
	var root := _burn_badges[unit] as Control
	if unit.burn_stacks <= 0 or not unit.is_alive():
		root.visible = false
		return
	root.visible = true
	var gem := root.get_node("Gem") as ColorRect
	var text := root.get_node("Text") as Label
	_apply_ui_label_font(text, 12)
	text.text = "燃%d" % unit.burn_stacks
	text.add_theme_color_override("font_color", BURN_BADGE_COLOR)
	gem.color = BURN_BADGE_COLOR
	text.reset_size()
	var gem_span := 11.0
	var gap := 2.0
	gem.position = Vector2(1.5, (maxf(text.size.y, gem_span) - 8.0) * 0.5)
	text.position = Vector2(gem_span + gap, 0.0)
	root.size = Vector2(
		gem_span + gap + text.size.x,
		maxf(text.size.y, gem_span)
	)
	var spr := _unit_sprites[unit] as Sprite2D
	var side_off := Vector2(config.unit_world_height * 0.55, -config.unit_world_height * 0.55)
	_position_world_on_label(root, _unit_world_position(spr) + side_off)
	_clamp_label_in_viewport(root)


func _ensure_frenzy_badge(unit: TacticalUnitInstance) -> void:
	if _frenzy_badges.has(unit):
		_update_frenzy_badge(unit)
		return
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	var gem := ColorRect.new()
	gem.name = "Gem"
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.size = Vector2(8, 8)
	gem.pivot_offset = Vector2(4, 4)
	gem.rotation_degrees = 45.0
	gem.color = FRENZY_BADGE_COLOR
	root.add_child(gem)
	var text := Label.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_ui_label_font(text, 12)
	text.add_theme_color_override("font_color", FRENZY_BADGE_COLOR)
	text.add_theme_color_override("font_outline_color", Color("2a0810"))
	text.add_theme_constant_override("outline_size", 4)
	root.add_child(text)
	_labels_root.add_child(root)
	_frenzy_badges[unit] = root
	_update_frenzy_badge(unit)


func _update_frenzy_badge(unit: TacticalUnitInstance) -> void:
	if not _frenzy_badges.has(unit) or not _unit_sprites.has(unit):
		return
	var root := _frenzy_badges[unit] as Control
	if unit.frenzy_stacks <= 0 or not unit.is_alive():
		root.visible = false
		return
	root.visible = true
	var gem := root.get_node("Gem") as ColorRect
	var text := root.get_node("Text") as Label
	_apply_ui_label_font(text, 12)
	text.text = "狂%d" % unit.frenzy_stacks
	text.add_theme_color_override("font_color", FRENZY_BADGE_COLOR)
	gem.color = FRENZY_BADGE_COLOR
	text.reset_size()
	var gem_span := 11.0
	var gap := 2.0
	gem.position = Vector2(1.5, (maxf(text.size.y, gem_span) - 8.0) * 0.5)
	text.position = Vector2(gem_span + gap, 0.0)
	root.size = Vector2(
		gem_span + gap + text.size.x,
		maxf(text.size.y, gem_span)
	)
	var spr := _unit_sprites[unit] as Sprite2D
	# 左侧角标，避开右侧燃烧。
	var side_off := Vector2(-config.unit_world_height * 0.7, -config.unit_world_height * 0.55)
	_position_world_on_label(root, _unit_world_position(spr) + side_off)
	_clamp_label_in_viewport(root)


func _ensure_intent_icon(unit: TacticalUnitInstance) -> void:
	if not TacticalEnemyAiScript.uses_behavior_sm(unit):
		if _intent_icons.has(unit):
			var stale: Control = _intent_icons[unit] as Control
			stale.queue_free()
			_intent_icons.erase(unit)
		return
	if _intent_icons.has(unit):
		_update_intent_icon(unit)
		return
	# Web 无系统字体：◆ 不在 Noto/Droid 字形表，改用旋转方块作菱形 + 中文 Label。
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gem := ColorRect.new()
	gem.name = "Gem"
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.size = Vector2(8, 8)
	gem.pivot_offset = Vector2(4, 4)
	gem.rotation_degrees = 45.0
	root.add_child(gem)
	var text := Label.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_ui_label_font(text, 12)
	text.add_theme_color_override("font_outline_color", Color("0a1018"))
	text.add_theme_constant_override("outline_size", 4)
	root.add_child(text)
	_labels_root.add_child(root)
	_intent_icons[unit] = root
	_update_intent_icon(unit)


func _update_intent_icon(unit: TacticalUnitInstance) -> void:
	if not _unit_sprites.has(unit):
		return
	if not TacticalEnemyAiScript.uses_behavior_sm(unit):
		if _intent_icons.has(unit):
			(_intent_icons[unit] as Control).visible = false
		return
	if not _intent_icons.has(unit):
		_ensure_intent_icon(unit)
		return
	var root := _intent_icons[unit] as Control
	if not unit.is_alive():
		root.visible = false
		return
	root.visible = true
	var gem := root.get_node("Gem") as ColorRect
	var text := root.get_node("Text") as Label
	# 占位意图角标：击/血/加/召，颜色区分；不挡中央血攻读数。
	var tint := Color("e8f0ff")
	match unit.next_intent:
		TacticalEnemyAiScript.Intent.MOVE_ATTACK:
			text.text = "击"
			tint = Color("ff8a7a")
		TacticalEnemyAiScript.Intent.HEAL:
			text.text = "血"
			tint = Color("7dff9a")
		TacticalEnemyAiScript.Intent.BUFF_ATK:
			text.text = "加"
			tint = Color("ffe08a")
		TacticalEnemyAiScript.Intent.SUMMON:
			text.text = "召"
			tint = Color("d4a0ff")
		_:
			text.text = "?"
			tint = Color("e8f0ff")
	text.add_theme_color_override("font_color", tint)
	gem.color = tint
	text.reset_size()
	# 菱形外接约 11px；文字紧挨右侧。
	var gem_span := 11.0
	var gap := 2.0
	gem.position = Vector2(1.5, (maxf(text.size.y, gem_span) - 8.0) * 0.5)
	text.position = Vector2(gem_span + gap, 0.0)
	root.size = Vector2(
		gem_span + gap + text.size.x,
		maxf(text.size.y, gem_span)
	)
	var spr := _unit_sprites[unit] as Sprite2D
	var side_off := Vector2(
		-config.unit_world_height * 0.62,
		-config.unit_world_height * 1.05
	)
	_position_world_on_label(root, _unit_world_position(spr) + side_off)
	_clamp_label_in_viewport(root)


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
	var present := _get_catalog().is_present(terrain_id)
	root.visible = present
	var grass: Polygon2D = root.get_node_or_null("Grass") as Polygon2D
	if not present:
		if grass != null:
			grass.polygon = PackedVector2Array()
		var ov_hide: Polygon2D = root.get_node_or_null("Overlay") as Polygon2D
		if ov_hide != null:
			ov_hide.visible = false
			ov_hide.polygon = PackedVector2Array()
		var wall_hide: Node2D = root.get_node_or_null("Wall") as Node2D
		if wall_hide != null:
			wall_hide.visible = false
		var forest_hide: Node2D = root.get_node_or_null("Forest") as Node2D
		if forest_hide != null:
			forest_hide.visible = false
		return
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
	if not _get_catalog().is_present(terrain_id_at(cell)):
		ov.visible = false
		return
	var tag := ""
	if cell == _overlay_selected:
		tag = "s"
	elif cell == _overlay_drag_hover:
		if _overlay_drag_hover_kind > 0:
			tag = "hv"
		elif _overlay_drag_hover_kind < 0:
			tag = "hx"
		else:
			tag = "h"
	elif _overlay_attack.has(cell):
		tag = "a"
	elif _overlay_skill_release.has(cell):
		tag = "sk"
	elif _overlay_move.has(cell) or _overlay_preview_move.has(cell):
		tag = "m"
	elif _overlay_intent_target.has(cell):
		tag = "it"
	elif _overlay_intent_path.has(cell):
		tag = "ip"
	ov.visible = tag != ""
	if tag != "":
		ov.color = OVERLAY_COLORS.get(tag, Color(1, 1, 1, 0.4)) as Color


func _clear_intent_preview() -> void:
	_overlay_intent_path.clear()
	_overlay_intent_target.clear()
	_intent_preview_unit = null
	if _intent_preview_ghost != null and is_instance_valid(_intent_preview_ghost):
		_intent_preview_ghost.queue_free()
	_intent_preview_ghost = null
	if _intent_preview_line != null and is_instance_valid(_intent_preview_line):
		_intent_preview_line.queue_free()
	_intent_preview_line = null
	if _intent_preview_hint != null and is_instance_valid(_intent_preview_hint):
		_intent_preview_hint.queue_free()
	_intent_preview_hint = null


func _sync_intent_preview(preview: Dictionary, unit: TacticalUnitInstance) -> void:
	_clear_intent_preview()
	if config == null or _units_root == null:
		return
	if preview.is_empty() or unit == null or not unit.is_alive():
		return
	var kind := String(preview.get("kind", "idle"))
	if kind == "idle":
		return
	_intent_preview_unit = unit
	var from_cell: Vector2i = preview.get("from", unit.cell) as Vector2i
	var to_cell: Vector2i = preview.get("to", Vector2i(-1, -1)) as Vector2i
	match kind:
		"move":
			var path: Array = preview.get("path", []) as Array
			if path.is_empty() and to_cell.x >= 0:
				path = [from_cell, to_cell]
			for c in path:
				if c is Vector2i:
					var cell := c as Vector2i
					if cell == from_cell:
						continue
					_overlay_intent_path[cell] = true
			if to_cell.x >= 0:
				_spawn_intent_ghost(unit, to_cell)
				_spawn_intent_path_line(path)
		"attack":
			if to_cell.x >= 0:
				_overlay_intent_target[to_cell] = true
				_spawn_intent_attack_line(from_cell, to_cell)
		"heal":
			var heal_amt := int(preview.get("amount", TacticalEnemyAiScript.HEAL_AMOUNT))
			_spawn_intent_hint(from_cell, "下回合·回血+%d" % heal_amt, Color("7dff9a"))
		"buff_atk":
			var buff_amt := int(preview.get("amount", TacticalEnemyAiScript.BUFF_ATK_AMOUNT))
			_spawn_intent_hint(from_cell, "下回合·加攻+%d" % buff_amt, Color("ffe08a"))
		"summon":
			var n := int(preview.get("amount", TacticalEnemyAiScript.SUMMON_COUNT))
			_spawn_intent_hint(from_cell, "下回合·召唤%d" % n, Color("d4a0ff"))
			var summon_cells: Array = preview.get("summon_cells", []) as Array
			for sc in summon_cells:
				if sc is Vector2i:
					_overlay_intent_path[sc as Vector2i] = true
		_:
			pass


func _spawn_intent_ghost(unit: TacticalUnitInstance, cell: Vector2i) -> void:
	var tex := unit.def.texture_red if unit.def != null else null
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.name = "IntentGhost"
	spr.centered = true
	spr.texture = tex
	spr.modulate = Color(0.75, 0.9, 1.0, INTENT_GHOST_ALPHA)
	spr.z_as_relative = false
	var metrics := _texture_content_metrics(tex)
	var content_h: float = metrics.content_h
	var vis := unit.def.visual_scale if unit.def.visual_scale > 0.0 else 1.0
	var s := (config.unit_world_height / content_h) * vis if content_h > 0.0 else 1.0
	spr.scale = Vector2(s, s)
	spr.offset = Vector2(0.0, metrics.offset_y)
	spr.position = _cell_to_world(cell, config.cell_size)
	spr.z_index = UNIT_Z_BASE + int(round(spr.position.y * 100.0)) + 2
	_units_root.add_child(spr)
	_intent_preview_ghost = spr


func _spawn_intent_path_line(path: Array) -> void:
	if path.size() < 2:
		return
	var line := Line2D.new()
	line.name = "IntentPathLine"
	line.width = maxf(config.cell_size * 0.12, 0.08)
	line.default_color = INTENT_PATH_LINE_COLOR
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_as_relative = false
	line.z_index = UNIT_Z_BASE - 20
	for c in path:
		if c is Vector2i:
			line.add_point(_cell_to_world(c as Vector2i, config.cell_size))
	_units_root.add_child(line)
	_intent_preview_line = line


func _spawn_intent_attack_line(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var line := Line2D.new()
	line.name = "IntentAttackLine"
	line.width = maxf(config.cell_size * 0.14, 0.1)
	line.default_color = INTENT_ATK_LINE_COLOR
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_as_relative = false
	line.z_index = UNIT_Z_BASE - 18
	var from_w := _cell_to_world(from_cell, config.cell_size)
	var to_w := _cell_to_world(to_cell, config.cell_size)
	line.add_point(from_w)
	line.add_point(to_w)
	# 箭头两翼（独立短线段叠在同一 Line2D 会折返；改用子 Line2D）。
	var dir := to_w - from_w
	if dir.length() > 0.001:
		var n := dir.normalized()
		var tip := to_w - n * (config.cell_size * 0.2)
		var perp := Vector2(-n.y, n.x) * (config.cell_size * 0.18)
		var wing_l := Line2D.new()
		wing_l.width = line.width
		wing_l.default_color = INTENT_ATK_LINE_COLOR
		wing_l.begin_cap_mode = Line2D.LINE_CAP_ROUND
		wing_l.end_cap_mode = Line2D.LINE_CAP_ROUND
		wing_l.add_point(to_w)
		wing_l.add_point(tip + perp)
		line.add_child(wing_l)
		var wing_r := Line2D.new()
		wing_r.width = line.width
		wing_r.default_color = INTENT_ATK_LINE_COLOR
		wing_r.begin_cap_mode = Line2D.LINE_CAP_ROUND
		wing_r.end_cap_mode = Line2D.LINE_CAP_ROUND
		wing_r.add_point(to_w)
		wing_r.add_point(tip - perp)
		line.add_child(wing_r)
	_units_root.add_child(line)
	_intent_preview_line = line


func _spawn_intent_hint(cell: Vector2i, text: String, color: Color) -> void:
	var root := Control.new()
	root.name = "IntentHint"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = text
	_apply_ui_label_font(lbl, 14)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color("0a1018"))
	lbl.add_theme_constant_override("outline_size", 4)
	root.add_child(lbl)
	_labels_root.add_child(root)
	lbl.reset_size()
	root.size = lbl.size
	var world := _cell_to_world(cell, config.cell_size)
	var head := Vector2(0.0, -config.unit_world_height * 1.55)
	_position_world_on_label(root, world + head)
	_clamp_label_in_viewport(root)
	_intent_preview_hint = root


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


## 拖牌/部署悬停：cell 为 null 时清空；unit 非空则播选中 scale 脉冲。
## valid_drop：可落=true（空格或合法目标）；悬停单位但不可落=false；空白无效格 unit=null。
func set_card_drag_hover(cell: Variant, unit: TacticalUnitInstance, valid_drop: bool) -> void:
	var prev_hover := _overlay_drag_hover
	if cell is Vector2i:
		_overlay_drag_hover = cell as Vector2i
		# 可落（含空格）一律绿；不可落且压在单位上为红；其余中性黄。
		if valid_drop:
			_overlay_drag_hover_kind = 1
		elif unit != null and unit.is_alive():
			_overlay_drag_hover_kind = -1
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


## 非通用技拖牌预览：高亮可释放格 + STS 曲线箭头（施法格 → 悬停格）。
## caster_cell / hover_cell 为 null 时只清箭头；release_cells 为空则清高亮。
func set_skill_drag_preview(
	caster_cell: Variant,
	hover_cell: Variant,
	release_cells: Array,
	hover_in_release: bool
) -> void:
	var prev_release := _overlay_skill_release.duplicate()
	_overlay_skill_release.clear()
	for c in release_cells:
		if c is Vector2i:
			_overlay_skill_release[c as Vector2i] = true
	for cell in prev_release.keys():
		_apply_overlay(cell as Vector2i)
	for cell in _overlay_skill_release.keys():
		_apply_overlay(cell as Vector2i)
	if caster_cell is Vector2i and hover_cell is Vector2i:
		_rebuild_skill_aim_arrow(
			caster_cell as Vector2i, hover_cell as Vector2i, hover_in_release
		)
	else:
		_clear_skill_aim_arrow()


func clear_skill_drag_preview() -> void:
	set_skill_drag_preview(null, null, [], false)


func clear_card_drag_hover() -> void:
	set_card_drag_hover(null, null, false)
	clear_skill_drag_preview()
	clear_action_preview()


func _clear_skill_aim_arrow() -> void:
	if _skill_aim_arrow != null and is_instance_valid(_skill_aim_arrow):
		_skill_aim_arrow.queue_free()
	_skill_aim_arrow = null


## 二次贝塞尔曲线箭头（杀戮尖塔式侧弯）+ 箭镞两翼。
func _rebuild_skill_aim_arrow(from_cell: Vector2i, to_cell: Vector2i, valid: bool) -> void:
	_clear_skill_aim_arrow()
	if config == null or _units_root == null:
		return
	var from_w := _cell_to_world(from_cell, config.cell_size)
	var to_w := _cell_to_world(to_cell, config.cell_size)
	var delta := to_w - from_w
	if delta.length() < 0.02:
		return
	var color := SKILL_ARROW_VALID if valid else SKILL_ARROW_INVALID
	var root := Node2D.new()
	root.name = "SkillAimArrow"
	root.z_as_relative = false
	# 高于单位层，避免被精灵挡住。
	root.z_index = UNIT_Z_BASE + 500
	var mid := (from_w + to_w) * 0.5
	var perp := Vector2(-delta.y, delta.x).normalized()
	# 侧弯幅度随距离增长，短距也保持可读弧。
	var bulge := clampf(delta.length() * 0.32, config.cell_size * 0.45, config.cell_size * 1.25)
	# 固定弯向屏幕上方偏好：若 perp 朝下则翻转。
	if perp.y > 0.0:
		perp = -perp
	var ctrl := mid + perp * bulge
	var shaft := Line2D.new()
	shaft.width = maxf(config.cell_size * 0.16, 0.12)
	shaft.default_color = color
	shaft.begin_cap_mode = Line2D.LINE_CAP_ROUND
	shaft.end_cap_mode = Line2D.LINE_CAP_ROUND
	shaft.joint_mode = Line2D.LINE_JOINT_ROUND
	for i in range(SKILL_ARROW_SEGMENTS + 1):
		var t := float(i) / float(SKILL_ARROW_SEGMENTS)
		var omt := 1.0 - t
		var p: Vector2 = (
			omt * omt * from_w
			+ 2.0 * omt * t * ctrl
			+ t * t * to_w
		)
		shaft.add_point(p)
	root.add_child(shaft)
	# 箭镞：沿曲线末端切线。
	var tip_dir := (to_w - ctrl).normalized()
	if tip_dir.length() < 0.001:
		tip_dir = delta.normalized()
	var tip := to_w
	var wing_base := tip - tip_dir * (config.cell_size * 0.36)
	var wing_perp := Vector2(-tip_dir.y, tip_dir.x) * (config.cell_size * 0.26)
	for side in [-1.0, 1.0]:
		var wing := Line2D.new()
		wing.width = shaft.width
		wing.default_color = color
		wing.begin_cap_mode = Line2D.LINE_CAP_ROUND
		wing.end_cap_mode = Line2D.LINE_CAP_ROUND
		wing.add_point(tip)
		wing.add_point(wing_base + wing_perp * side)
		root.add_child(wing)
	_units_root.add_child(root)
	_skill_aim_arrow = root


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
	var center_proj := _cell_to_world(cell, config.cell_size)
	root.position = center_proj
	if not _get_catalog().is_present(terrain_id_at(cell)):
		var grass_void: Polygon2D = root.get_node("Grass") as Polygon2D
		grass_void.polygon = PackedVector2Array()
		var ov_void: Polygon2D = root.get_node("Overlay") as Polygon2D
		ov_void.polygon = PackedVector2Array()
		root.visible = false
		return
	var half := config.cell_size * config.tile_inset * 0.5
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
	root.visible = true
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
		else:
			_emit_pointer_hover(mm.position)


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
	## 竖向：往下滑动 → 视角往下（+forward）；左右仍为「抓住地图」跟手（-right）。
	var cam_z := _camera.zoom.y if _camera != null and _camera.zoom.y > 0.0 else 1.0
	var scaled := delta / maxf(cam_z, 0.001) * config.camera_pan_sensitivity
	var yaw := deg_to_rad(config.camera_yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	return -right * scaled.x + forward * scaled.y


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
			_start_deploy_unit_drag(_press_unit)
	if dist >= LONG_PRESS_SLOP_PX:
		_cancel_long_press()
		if _deploy_drag_unit == null:
			_press_unit = null
	if _deploy_drag_unit != null:
		_update_deploy_unit_drag(local_pos)
		var cell_v: Variant = _pick_cell(local_pos)
		if cell_v == null:
			clear_card_drag_hover()
		else:
			var cell: Vector2i = cell_v
			var valid := _deploy_drop_valid_at(cell)
			var occupant := _unit_under_cell(cell)
			var pulse: TacticalUnitInstance = null
			# 换位时脉冲目标友方；空格只标绿，不脉冲自己。
			if occupant != null and occupant != _deploy_drag_unit:
				pulse = occupant
			set_card_drag_hover(cell, pulse, valid)
		return
	if _drag_moved and not _info_shown:
		_pan_by_screen_delta(delta)


func _start_deploy_unit_drag(unit: TacticalUnitInstance) -> void:
	_deploy_drag_unit = unit
	_cancel_long_press()
	_pause_unit_idle(unit)
	_kill_unit_move_tween(unit)
	if _drag_select_unit == unit:
		_clear_drag_select_unit()
	else:
		_kill_unit_select_tween(unit)
	var spr := _unit_sprites.get(unit) as Sprite2D
	if spr == null:
		return
	_float_unit_for_world_tween(spr)
	spr.z_as_relative = false
	spr.z_index = UNIT_Z_BASE + 8000


func _update_deploy_unit_drag(local_pos: Vector2) -> void:
	if _deploy_drag_unit == null or not _unit_sprites.has(_deploy_drag_unit):
		return
	var spr := _unit_sprites[_deploy_drag_unit] as Sprite2D
	_float_unit_for_world_tween(spr)
	spr.position = _local_to_world(local_pos)
	spr.z_as_relative = false
	spr.z_index = UNIT_Z_BASE + 8000


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
		# 松手先不弹回旧格：合法落点由沙盘 accept；失败/越界再 cancel。
		_deploy_drag_unit = null
		_press_unit = null
		_suppress_click = true
		if cell_v != null:
			unit_deploy_dropped.emit(dropped, cell_v as Vector2i)
		else:
			cancel_deploy_drag_visual(dropped)
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
	# 先按精灵包围盒抓取（高立绘头顶常不在格心），再回退格点。
	if _camera != null and config != null and size.x > 0.0 and size.y > 0.0:
		var world := _local_to_world(local_pos)
		var best: TacticalUnitInstance = null
		var best_z := -2147483648
		for key in _unit_sprites.keys():
			var u := key as TacticalUnitInstance
			if u == null or not u.is_alive():
				continue
			if _deploy_mode and u.faction != TacticalFactionScript.Id.PLAYER:
				continue
			var spr := _unit_sprites[u] as Sprite2D
			if not _sprite_hits_world(spr, world):
				continue
			if spr.z_index >= best_z:
				best_z = spr.z_index
				best = u
		if best != null:
			return best
	var cell: Variant = _pick_cell(local_pos)
	if cell == null:
		return null
	var c := cell as Vector2i
	for key in _unit_sprites.keys():
		var u := key as TacticalUnitInstance
		if u == null or not u.is_alive() or u.cell != c:
			continue
		if _deploy_mode and u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		return u
	return null


func _sprite_hits_world(spr: Sprite2D, world: Vector2) -> bool:
	if spr == null or not is_instance_valid(spr) or spr.texture == null:
		return false
	var lr := spr.get_rect()
	var sc := spr.scale
	var origin := _unit_world_position(spr) + Vector2(lr.position.x * sc.x, lr.position.y * sc.y)
	var rect_size := Vector2(lr.size.x * absf(sc.x), lr.size.y * absf(sc.y))
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return false
	# 略放大便于点按立绘边缘。
	var pad := rect_size * 0.08
	return Rect2(origin - pad * 0.5, rect_size + pad).has_point(world)


func _local_to_world(local_pos: Vector2) -> Vector2:
	if _camera == null or not _camera.is_inside_tree():
		return local_pos
	var vp_pos := _to_viewport_pos(local_pos)
	return _camera.get_canvas_transform().affine_inverse() * vp_pos


## 单位贴图在沙盘屏幕上的显示尺寸（与棋盘 Sprite2D 一致，含相机 zoom 与 SubViewport stretch）。
func unit_texture_screen_size(tex: Texture2D, visual_scale: float = 1.0) -> Vector2:
	if tex == null or config == null:
		return Vector2.ZERO
	var metrics := _texture_content_metrics(tex)
	var content_h: float = metrics.content_h
	var vis := visual_scale if visual_scale > 0.0 else 1.0
	var s := (config.unit_world_height / content_h) * vis if content_h > 0.0 else 1.0
	var world_sz := tex.get_size() * s
	var cam_z := _camera.zoom.y if _camera != null and _camera.zoom.y > 0.0 else 1.0
	var vp_sz := world_sz * cam_z
	if _viewport == null or _viewport_container == null:
		return vp_sz
	var vs := _viewport.size
	var cs := _viewport_container.size
	if vs.x <= 0 or vs.y <= 0 or cs.x <= 0.0 or cs.y <= 0.0:
		return vp_sz
	return Vector2(vp_sz.x * cs.x / float(vs.x), vp_sz.y * cs.y / float(vs.y))


## 单位标记中心（全局屏幕坐标），供击杀剪影锚点。
func unit_screen_position(unit: TacticalUnitInstance) -> Vector2:
	if unit == null or not _unit_sprites.has(unit) or _camera == null:
		return get_global_rect().get_center()
	var spr := _unit_sprites[unit] as Sprite2D
	return _world_to_screen(_unit_world_position(spr))


## 单位头顶锚点（全局屏幕坐标），供信息卡定位。
func unit_head_global_position(unit: TacticalUnitInstance) -> Vector2:
	if unit == null or not _unit_sprites.has(unit) or _camera == null:
		return get_global_rect().get_center()
	var spr := _unit_sprites[unit] as Sprite2D
	var world := _unit_world_position(spr) + Vector2(0.0, -config.unit_world_height * 1.05)
	return _world_to_screen(world)


func _world_to_screen(world: Vector2) -> Vector2:
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


func _emit_pointer_hover(local_pos: Vector2) -> void:
	var cell_v: Variant = _pick_cell(local_pos)
	var key := Vector2i(-999, -999)
	if cell_v is Vector2i:
		key = cell_v as Vector2i
	if key == _pointer_hover_cell:
		return
	_pointer_hover_cell = key
	if cell_v is Vector2i:
		cell_hovered.emit(cell_v)
	else:
		cell_hovered.emit(null)


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
	if guess is Vector2i and _get_catalog().is_present(terrain_id_at(guess as Vector2i)):
		if _world_hits_cell_poly(world, guess as Vector2i):
			return guess
	# 否则扫全部可见格：取屏幕纵深最大者（更靠前、与绘制一致）。
	var best: Variant = null
	var best_z := -2147483648
	for cell in _tile_nodes.keys():
		var c: Vector2i = cell as Vector2i
		if not _get_catalog().is_present(terrain_id_at(c)):
			continue
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