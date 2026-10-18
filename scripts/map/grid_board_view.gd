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
var _mesh_cache: Dictionary = {}
var _mat_cache: Dictionary = {}

var _target: Vector3 = Vector3.ZERO
var _zoom: float = 1.0
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _press_pos: Vector2 = Vector2.ZERO
var _needs_center: bool = true

const DRAG_THRESHOLD_PX := 6.0


func setup(p_config: BoardConfig) -> void:
	config = p_config
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_viewport_tree()
	_zoom = clampf(config.camera_zoom_default, config.camera_zoom_min, config.camera_zoom_max)
	_needs_center = true
	_rebuild_board()
	_try_center_on_board()
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
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport_container.add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "BoardWorld"
	_viewport.add_child(_world_root)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	light.light_energy = 1.25
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


func _on_resized() -> void:
	if config == null:
		return
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

	var cell_size := config.cell_size
	for gx in range(config.grid_width):
		for gy in range(config.grid_height):
			var cell := Vector2i(gx, gy)
			var mi := MeshInstance3D.new()
			mi.position = _cell_to_world(cell, cell_size)
			_tiles_root.add_child(mi)
			_tile_nodes[cell] = mi
			_apply_tile_visual(cell)

	_spawn_placeholder_units()


func _apply_tile_visual(cell: Vector2i) -> void:
	if config == null or not _tile_nodes.has(cell):
		return
	var mi: MeshInstance3D = _tile_nodes[cell] as MeshInstance3D
	var inset := config.cell_size * config.tile_inset
	var height := config.tile_height
	var key := "%.3f_%.3f" % [inset, height]
	if not _mesh_cache.has(key):
		var box := BoxMesh.new()
		box.size = Vector3(inset, height, inset)
		_mesh_cache[key] = box
	mi.mesh = _mesh_cache[key] as Mesh
	var checker := (cell.x + cell.y) % 2 == 0
	var color := config.color_light if checker else config.color_dark
	mi.material_override = _material_for("tile_%d" % int(checker), color)


func _material_for(key: String, color: Color) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.albedo_color = color
	mat.roughness = 0.88
	_mat_cache[key] = mat
	return mat


func _spawn_placeholder_units() -> void:
	# 双方各一占位精灵，便于验证 Z 序与格点对齐。
	_add_unit_sprite(Vector2i(2, 3), Color("4a9fd4"), "player")
	_add_unit_sprite(Vector2i(7, 4), Color("d45a4a"), "opponent")


func _add_unit_sprite(cell: Vector2i, tint: Color, label: String) -> void:
	var spr := Sprite3D.new()
	spr.texture = _unit_placeholder_texture(tint)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = 0.008
	spr.modulate = Color.WHITE
	spr.name = "Unit_%s" % label
	var world := _cell_to_world(cell, config.cell_size)
	spr.position = Vector3(world.x, config.tile_height + 0.55, world.z)
	_units_root.add_child(spr)


static func _unit_placeholder_texture(tint: Color) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(tint)
	# 简单描边便于在格子上辨认。
	for i in range(64):
		img.set_pixel(i, 0, Color.BLACK)
		img.set_pixel(i, 63, Color.BLACK)
		img.set_pixel(0, i, Color.BLACK)
		img.set_pixel(63, i, Color.BLACK)
	return ImageTexture.create_from_image(img)


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
	_zoom = clampf(value, config.camera_zoom_min, config.camera_zoom_max)
	_clamp_target()
	_apply_camera()


func _pan_by_screen_delta(delta: Vector2) -> void:
	var sens := config.camera_pan_sensitivity / maxf(_zoom, 0.05)
	var yaw := deg_to_rad(config.camera_yaw_deg)
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
	var from := _camera.project_ray_origin(local_pos)
	var dir := _camera.project_ray_normal(local_pos)
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


func _clamp_target() -> void:
	var cell_size := config.cell_size
	var half_w := float(config.grid_width) * cell_size * 0.5
	var half_h := float(config.grid_height) * cell_size * 0.5
	var pad := cell_size * 1.5
	_target.x = clampf(_target.x, -half_w - pad, half_w + pad)
	_target.z = clampf(_target.z, -half_h - pad, half_h + pad)
	_target.y = 0.0
