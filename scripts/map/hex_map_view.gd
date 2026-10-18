class_name HexMapView
extends Control
## 文明式 ~45° 俯视 3D 六边地图：棱柱地形、迷雾、拖拽/滚轮镜头。逻辑在 HexMapModel。


const Terrain := preload("res://scripts/map/terrain_type.gd")
const Hex := preload("res://scripts/map/hex_coords.gd")
const HexMeshBuilderScript := preload("res://scripts/map/hex_mesh_builder.gd")

signal cell_clicked(cell: Vector2i)

var model: HexMapModel
var viewing_side: int = StrategicFog.Side.PLAYER

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world_root: Node3D
var _tiles_root: Node3D
var _camera: Camera3D
var _pivot: Node3D
var _tile_nodes: Dictionary = {} # Vector2i -> MeshInstance3D
var _mesh_cache: Dictionary = {} # String -> ArrayMesh
var _mat_cache: Dictionary = {} # String -> StandardMaterial3D

var _target: Vector3 = Vector3.ZERO
var _zoom: float = 1.0
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _press_pos: Vector2 = Vector2.ZERO
var _needs_center: bool = true

const DRAG_THRESHOLD_PX := 6.0
const CAMERA_YAW_DEG := 35.0


func setup(p_model: HexMapModel) -> void:
	model = p_model
	if not model.changed.is_connected(_on_model_changed):
		model.changed.connect(_on_model_changed)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_viewport_tree()
	_zoom = clampf(model.config.camera_zoom_default, model.config.camera_zoom_min, model.config.camera_zoom_max)
	_needs_center = true
	_rebuild_tiles()
	_try_center_on_origin()
	_apply_camera()


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
	# 软光栅下 MSAA 成本高；占位地形以清晰色块为主。
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	# stretch=true 时由容器驱动尺寸，勿再手改 SubViewport.size。
	_viewport_container.add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "HexWorld"
	_viewport.add_child(_world_root)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	light.light_energy = 1.15
	light.shadow_enabled = false
	_world_root.add_child(light)

	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1a2430")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6a7a8c")
	env.ambient_light_energy = 0.55
	ambient.environment = env
	_world_root.add_child(ambient)

	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_world_root.add_child(_pivot)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 42.0
	_camera.near = 0.1
	_camera.far = 400.0
	_pivot.add_child(_camera)

	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	_world_root.add_child(_tiles_root)


func _on_model_changed() -> void:
	_refresh_tile_visuals()
	_clamp_target()
	_apply_camera()


func _on_resized() -> void:
	if model == null:
		return
	if _needs_center:
		_try_center_on_origin()
	_apply_camera()


func _try_center_on_origin() -> void:
	if size.x <= 1.0 or size.y <= 1.0 or model == null:
		return
	_target = Vector3.ZERO
	_needs_center = false
	_clamp_target()
	_apply_camera()


func _rebuild_tiles() -> void:
	if model == null or _tiles_root == null:
		return
	for child in _tiles_root.get_children():
		child.queue_free()
	_tile_nodes.clear()
	var hex_size := model.config.hex_size
	for cell in model.all_cells():
		var mi := MeshInstance3D.new()
		mi.position = _cell_to_world(cell, hex_size)
		_tiles_root.add_child(mi)
		_tile_nodes[cell] = mi
	_refresh_tile_visuals()


func _refresh_tile_visuals() -> void:
	if model == null:
		return
	var hex_size := model.config.hex_size
	var inset := hex_size * 0.94
	for cell in _tile_nodes.keys():
		var mi: MeshInstance3D = _tile_nodes[cell] as MeshInstance3D
		var revealed := model.fog.is_revealed(viewing_side, cell)
		var tid := model.terrain_at(cell)
		var height: float
		var mat: StandardMaterial3D
		if revealed:
			height = Terrain.placeholder_height(tid)
			mat = _material_for("t_%d" % tid, Terrain.placeholder_color(tid), false)
		else:
			height = 0.35
			mat = _material_for("fog", model.config.fog_color, false)
			if model.fog.can_reveal(viewing_side, cell, model.config.map_radius):
				mat = _material_for("fog_edge", Color("5a6a80"), true)
		var key := "%.2f_%.2f" % [inset, height]
		if not _mesh_cache.has(key):
			_mesh_cache[key] = HexMeshBuilderScript.build_prism(inset, height)
		mi.mesh = _mesh_cache[key] as ArrayMesh
		mi.material_override = mat


func _material_for(key: String, color: Color, emissive_edge: bool) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.albedo_color = color
	mat.roughness = 0.85
	if emissive_edge:
		mat.emission_enabled = true
		mat.emission = Color("9eb0c8")
		mat.emission_energy_multiplier = 0.35
	_mat_cache[key] = mat
	return mat


func _cell_to_world(cell: Vector2i, hex_size: float) -> Vector3:
	var p := Hex.axial_to_pixel(cell, hex_size)
	return Vector3(p.x, 0.0, p.y)


func _apply_camera() -> void:
	if _camera == null or _pivot == null or model == null:
		return
	_pivot.position = _target
	_pivot.rotation_degrees = Vector3(0.0, CAMERA_YAW_DEG, 0.0)
	var dist := model.config.camera_distance / maxf(_zoom, 0.05)
	var pitch_deg := model.config.camera_pitch_deg
	var pitch := deg_to_rad(pitch_deg)
	# 俯角约 45°：局部位移 + 俯仰，避免依赖 global look_at（入树前也安全）。
	_camera.position = Vector3(0.0, sin(pitch) * dist, cos(pitch) * dist)
	_camera.rotation_degrees = Vector3(-pitch_deg, 0.0, 0.0)


func _gui_input(event: InputEvent) -> void:
	if model == null or _camera == null:
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
		var mm := event as InputEventMouseMotion
		if _dragging and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var delta := mm.position - _drag_last
			_drag_last = mm.position
			if not _drag_moved and _press_pos.distance_to(mm.position) >= DRAG_THRESHOLD_PX:
				_drag_moved = true
			if _drag_moved:
				_pan_by_screen_delta(delta)
				accept_event()


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, model.config.camera_zoom_min, model.config.camera_zoom_max)
	_clamp_target()
	_apply_camera()


func _pan_by_screen_delta(delta: Vector2) -> void:
	# 屏幕拖拽：右拖世界右移感 → 目标反向；结合 yaw 投影到 XZ。
	var sens := model.config.camera_pan_sensitivity / maxf(_zoom, 0.05)
	var yaw := deg_to_rad(CAMERA_YAW_DEG)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	_target += -right * delta.x * sens + forward * delta.y * sens
	_clamp_target()
	_apply_camera()


func _handle_click(local_pos: Vector2) -> void:
	var cell: Variant = _pick_cell(local_pos)
	if cell == null:
		return
	cell_clicked.emit(cell as Vector2i)


func _pick_cell(local_pos: Vector2) -> Variant:
	if _camera == null or size.y <= 0.0 or not _camera.is_inside_tree():
		return null
	# SubViewportContainer.stretch：容器坐标与视口像素一致。
	var screen := local_pos
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	var hit := from + dir * t
	var cell := Hex.pixel_to_axial(Vector2(hit.x, hit.z), model.config.hex_size)
	if not Hex.in_radius(cell, model.config.map_radius):
		return null
	return cell


## 镜头可拖至覆盖已解锁格；缩放仅手动；不随解锁改默认缩放。
func _clamp_target() -> void:
	var hex_size := model.config.hex_size
	var revealed := model.fog.revealed_cells(viewing_side)
	if revealed.is_empty():
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for cell in revealed:
		var p := Hex.axial_to_pixel(cell, hex_size)
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var pad := hex_size * 2.5
	_target.x = clampf(_target.x, min_p.x - pad, max_p.x + pad)
	_target.z = clampf(_target.z, min_p.y - pad, max_p.y + pad)
	_target.y = 0.0
