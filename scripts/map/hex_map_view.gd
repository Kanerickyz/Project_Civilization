class_name HexMapView
extends Control
## 六边地图表现：色块地形、迷雾、拖拽平移。逻辑在 HexMapModel。


const Terrain := preload("res://scripts/map/terrain_type.gd")
const Hex := preload("res://scripts/map/hex_coords.gd")

signal cell_clicked(cell: Vector2i)

var model: HexMapModel
var viewing_side: int = StrategicFog.Side.PLAYER

var _pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _press_pos: Vector2 = Vector2.ZERO
var _needs_center: bool = true

const DRAG_THRESHOLD_PX := 6.0


func setup(p_model: HexMapModel) -> void:
	model = p_model
	if not model.changed.is_connected(_on_model_changed):
		model.changed.connect(_on_model_changed)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_needs_center = true
	_try_center_on_origin()
	queue_redraw()


func _on_model_changed() -> void:
	queue_redraw()


func _try_center_on_origin() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	_pan = size * 0.5
	_needs_center = false


func _ready() -> void:
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if model == null:
		return
	if _needs_center:
		_try_center_on_origin()
	queue_redraw()


func _draw() -> void:
	if model == null:
		return
	var hex_size := model.config.hex_size
	var fog_color := model.config.fog_color
	for cell in model.all_cells():
		var center := Hex.axial_to_pixel(cell, hex_size) + _pan
		if not _hex_may_be_visible(center, hex_size):
			continue
		var corners := Hex.hex_corners(center, hex_size * 0.96)
		var revealed := model.fog.is_revealed(viewing_side, cell)
		if revealed:
			draw_colored_polygon(corners, Terrain.placeholder_color(model.terrain_at(cell)))
			draw_polyline(corners + PackedVector2Array([corners[0]]), Color("1e2a3288"), 1.0, true)
		else:
			draw_colored_polygon(corners, fog_color)
			if model.fog.can_reveal(viewing_side, cell, model.config.map_radius):
				draw_polyline(corners + PackedVector2Array([corners[0]]), Color("c9d4e066"), 1.2, true)


func _hex_may_be_visible(center: Vector2, hex_size: float) -> bool:
	var pad := hex_size * 1.2
	return center.x > -pad and center.y > -pad and center.x < size.x + pad and center.y < size.y + pad


func _gui_input(event: InputEvent) -> void:
	if model == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
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
				_pan += delta
				_clamp_pan()
				queue_redraw()
				accept_event()


func _handle_click(local_pos: Vector2) -> void:
	var world := local_pos - _pan
	var cell := Hex.pixel_to_axial(world, model.config.hex_size)
	if not Hex.in_radius(cell, model.config.map_radius):
		return
	cell_clicked.emit(cell)


## 镜头可拖至覆盖已解锁格；不随解锁改缩放。可改夹紧策略。
func _clamp_pan() -> void:
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
	var pad := hex_size * 2.0
	var min_pan := Vector2(size.x * 0.15, size.y * 0.15) - max_p - Vector2(pad, pad)
	var max_pan := Vector2(size.x * 0.85, size.y * 0.85) - min_p + Vector2(pad, pad)
	_pan.x = clampf(_pan.x, minf(min_pan.x, max_pan.x), maxf(min_pan.x, max_pan.x))
	_pan.y = clampf(_pan.y, minf(min_pan.y, max_pan.y), maxf(min_pan.y, max_pan.y))
