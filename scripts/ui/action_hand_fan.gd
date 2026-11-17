class_name ActionHandFan
extends Control
## 底栏扇形/横向重叠长方形手牌。
## 长按 0.35s 看详情（松手即关）；拖到目标点才算使用；无效松手回弹回手。


signal card_dropped(index: int, global_pos: Vector2)
## 拖拽跟手时持续发出，供棋盘悬停格/单位选中反馈（松手后由沙盘清空）。
signal card_drag_moved(index: int, global_pos: Vector2)

const CARD_W := 72.0
const CARD_H := 100.0
const OVERLAP := 38.0
const FAN_MAX_DEG := 10.0
const LIFT_Y := -22.0
const HOVER_SCALE := 1.12
const DRAG_SCALE := 1.22
const LONG_PRESS_SEC := 0.35
const DRAG_THRESHOLD_PX := 12.0
const TWEEN_SEC := 0.18

var _cards: Array[Control] = []
var _base_poses: Array[Dictionary] = []
var _hover_index: int = -1
var _interactive: bool = true
var _labels: Array[String] = []
var _kinds: Array[int] = []
var _detail_lines: Array[String] = []

var _press_index: int = -1
var _press_pos: Vector2 = Vector2.ZERO
var _press_global: Vector2 = Vector2.ZERO
var _long_press_timer: Timer
var _detail_open: bool = false
var _dragging: bool = false
var _drag_index: int = -1
var _drag_offset: Vector2 = Vector2.ZERO
var _busy: bool = false
var _detail_panel: PanelContainer
var _detail_title: Label
var _detail_body: Label


func _ready() -> void:
	# 根节点 IGNORE：空白区不挡棋盘；单卡 Panel 仍 STOP 接收拖拽/长按。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	custom_minimum_size = Vector2(320, 118)
	resized.connect(_relayout)
	_long_press_timer = Timer.new()
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = LONG_PRESS_SEC
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)
	_build_detail_panel()


func is_busy() -> bool:
	return _busy or _dragging or _detail_open or _press_index >= 0


func set_interactive(enabled: bool) -> void:
	_interactive = enabled
	if not enabled:
		_cancel_press_state(true)
	for c in _cards:
		c.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)
		c.modulate.a = 1.0 if enabled else 0.55


func set_hand(labels: Array[String], kinds: Array[int], details: Array[String] = []) -> void:
	if is_busy() and _cards.size() == labels.size():
		# 拖拽/详情中避免整手重建打断动画；仅更新文案缓存。
		_labels = labels.duplicate()
		_kinds = kinds.duplicate()
		_detail_lines = details.duplicate()
		return
	_cancel_press_state(false)
	_labels = labels.duplicate()
	_kinds = kinds.duplicate()
	_detail_lines = details.duplicate()
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_base_poses.clear()
	_hover_index = -1
	for i in _labels.size():
		var card := _make_card(
			_labels[i],
			int(_kinds[i]) if i < _kinds.size() else 0,
			i
		)
		add_child(card)
		_cards.append(card)
	_relayout()


func clear_hand() -> void:
	var empty_s: Array[String] = []
	var empty_k: Array[int] = []
	var empty_d: Array[String] = []
	set_hand(empty_s, empty_k, empty_d)


func notify_drop_resolved(accepted: bool) -> void:
	if not _dragging:
		return
	if accepted:
		_finish_accepted_drop()
	else:
		_snap_back_drag()


func _build_detail_panel() -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.visible = false
	_detail_panel.z_index = 200
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.custom_minimum_size = Vector2(200, 150)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	style.border_color = Color(0.85, 0.78, 0.55, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 8
	_detail_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(box)
	_detail_title = Label.new()
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_title.add_theme_color_override("font_color", Color("f5f0e0"))
	_detail_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_detail_title)
	_detail_body = Label.new()
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.add_theme_font_size_override("font_size", 13)
	_detail_body.add_theme_color_override("font_color", Color("d5dbe4"))
	_detail_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_detail_body)
	add_child(_detail_panel)


func _make_card(text: String, kind: int, index: int) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(CARD_W, CARD_H)
	panel.size = Vector2(CARD_W, CARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.focus_mode = Control.FOCUS_NONE
	panel.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)

	var style := StyleBoxFlat.new()
	if kind == 1:
		# 攻击
		style.bg_color = Color(0.42, 0.14, 0.16, 0.97)
		style.border_color = Color(0.85, 0.45, 0.4, 1.0)
	elif kind == 2 or kind == 3 or kind == 4:
		# 主动技（换手 / 加强攻 / 燃爆）
		style.bg_color = Color(0.28, 0.22, 0.12, 0.97)
		style.border_color = Color(0.9, 0.72, 0.35, 1.0)
	else:
		# 移动
		style.bg_color = Color(0.14, 0.36, 0.28, 0.97)
		style.border_color = Color(0.45, 0.8, 0.6, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6
	col.offset_top = 10
	col.offset_right = -6
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var kind_lbl := Label.new()
	kind_lbl.text = text
	kind_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kind_lbl.add_theme_font_size_override("font_size", 15)
	kind_lbl.add_theme_color_override("font_color", Color("f5f7fa"))
	kind_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(kind_lbl)

	var sub := Label.new()
	sub.text = "通用"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.85))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)

	panel.mouse_entered.connect(_on_card_hover.bind(index))
	panel.mouse_exited.connect(_on_card_unhover.bind(index))
	panel.gui_input.connect(_on_card_gui_input.bind(index))
	return panel


func _relayout(animate: bool = false) -> void:
	var n := _cards.size()
	if n == 0:
		custom_minimum_size.y = 118.0
		return
	var step := CARD_W - OVERLAP
	var total_w := CARD_W + step * float(n - 1)
	var origin_x := (size.x - total_w) * 0.5
	if origin_x < 0.0:
		origin_x = 0.0
		if n > 1:
			step = (size.x - CARD_W) / float(n - 1)
			total_w = size.x
	var base_y := size.y - CARD_H - 4.0
	_base_poses.clear()
	for i in n:
		var t := 0.0 if n == 1 else (float(i) / float(n - 1)) * 2.0 - 1.0
		var rot := t * FAN_MAX_DEG
		var arc_y := absf(t) * 6.0
		# 拖拽中的牌留出空隙：其余牌向中靠拢一点
		var gap_shift := 0.0
		if _dragging and _drag_index >= 0 and i != _drag_index:
			gap_shift = 10.0 if i < _drag_index else -10.0
		var pos := Vector2(origin_x + step * float(i) + gap_shift, base_y + arc_y)
		_base_poses.append({"pos": pos, "rot": rot})
		var card := _cards[i]
		if i == _drag_index and _dragging:
			continue
		card.z_index = i
		if animate:
			_tween_card_to(card, pos, rot, Vector2.ONE)
		elif i != _hover_index:
			card.position = pos
			card.rotation_degrees = rot
			card.scale = Vector2.ONE
	custom_minimum_size = Vector2(maxi(int(total_w) + 16, 280), 118)
	if not _dragging:
		_apply_hover_visual()


func _tween_card_to(card: Control, pos: Vector2, rot: float, scl: Vector2) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "position", pos, TWEEN_SEC).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(card, "rotation_degrees", rot, TWEEN_SEC).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(card, "scale", scl, TWEEN_SEC).set_trans(Tween.TRANS_QUAD)


func _on_card_hover(index: int) -> void:
	if not _interactive or _dragging:
		return
	_hover_index = index
	_apply_hover_visual()


func _on_card_unhover(index: int) -> void:
	if _hover_index == index and not _dragging:
		_hover_index = -1
		_apply_hover_visual()


func _apply_hover_visual() -> void:
	for i in _cards.size():
		if i >= _base_poses.size():
			continue
		if _dragging and i == _drag_index:
			continue
		var card := _cards[i]
		var base: Dictionary = _base_poses[i]
		var pos: Vector2 = base["pos"]
		var rot: float = base["rot"]
		if i == _hover_index and not _detail_open:
			card.z_index = 100
			_tween_card_to(card, pos + Vector2(0, LIFT_Y), rot * 0.25, Vector2(HOVER_SCALE, HOVER_SCALE))
		else:
			card.z_index = i
			card.position = pos
			card.rotation_degrees = rot
			card.scale = Vector2.ONE


func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_begin_press(index, mb)
			accept_event()
		else:
			# 释放多半在 _input 里处理（拖出控件后）
			pass


func _begin_press(index: int, mb: InputEventMouseButton) -> void:
	_cancel_press_state(false)
	_press_index = index
	_press_pos = mb.position
	_press_global = mb.global_position
	_dragging = false
	_drag_index = -1
	_detail_open = false
	_long_press_timer.start()
	set_process_input(true)


func _on_long_press_timeout() -> void:
	if _press_index < 0 or _dragging:
		return
	_show_detail(_press_index)


func _show_detail(index: int) -> void:
	if index < 0 or index >= _labels.size():
		return
	_detail_open = true
	_detail_title.text = _labels[index]
	if index < _detail_lines.size() and _detail_lines[index] != "":
		_detail_body.text = _detail_lines[index]
	else:
		_detail_body.text = "长按查看 · 拖到己方单位使用"
	_detail_panel.visible = true
	_detail_panel.scale = Vector2(0.92, 0.92)
	_detail_panel.modulate.a = 0.0
	# 放在手牌上方中央
	var target := Vector2((size.x - 200.0) * 0.5, -150.0)
	_detail_panel.position = target
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_detail_panel, "modulate:a", 1.0, 0.12)
	tw.tween_property(_detail_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)


func _hide_detail() -> void:
	if not _detail_open and not _detail_panel.visible:
		return
	_detail_open = false
	_detail_panel.visible = false


func _input(event: InputEvent) -> void:
	if _press_index < 0 and not _dragging:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		if not _dragging:
			var dist := mm.global_position.distance_to(_press_global)
			if dist >= DRAG_THRESHOLD_PX:
				_long_press_timer.stop()
				_hide_detail()
				_start_drag(_press_index, mm.global_position)
		if _dragging:
			_follow_drag(mm.global_position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_on_press_released(mb.global_position)
			get_viewport().set_input_as_handled()


func _start_drag(index: int, global_pos: Vector2) -> void:
	if index < 0 or index >= _cards.size():
		return
	_dragging = true
	_busy = true
	_drag_index = index
	_hover_index = -1
	var card := _cards[index]
	_drag_offset = card.size * 0.5
	card.z_index = 300
	card.set_as_top_level(true)
	card.global_position = global_pos - _drag_offset
	card.rotation_degrees = 0.0
	card.scale = Vector2(DRAG_SCALE, DRAG_SCALE)
	_relayout(true)
	card_drag_moved.emit(index, global_pos)


func _follow_drag(global_pos: Vector2) -> void:
	if _drag_index < 0 or _drag_index >= _cards.size():
		return
	var card := _cards[_drag_index]
	# 轻微跟手平滑
	var target := global_pos - _drag_offset
	card.global_position = card.global_position.lerp(target, 0.55)
	card_drag_moved.emit(_drag_index, global_pos)


func _on_press_released(global_pos: Vector2) -> void:
	_long_press_timer.stop()
	if _dragging:
		card_dropped.emit(_drag_index, global_pos)
		# 等待 sandbox notify_drop_resolved
		return
	# 长按详情：松手即关，卡仍在手；短按无效果。
	_hide_detail()
	_press_index = -1
	set_process_input(false)
	_apply_hover_visual()


func _finish_accepted_drop() -> void:
	if _drag_index >= 0 and _drag_index < _cards.size():
		var card := _cards[_drag_index]
		card.set_as_top_level(false)
		card.visible = false
	_dragging = false
	_drag_index = -1
	_press_index = -1
	_busy = false
	set_process_input(false)
	_hide_detail()


func _snap_back_drag() -> void:
	if _drag_index < 0 or _drag_index >= _cards.size():
		_cancel_press_state(true)
		return
	var idx := _drag_index
	var card := _cards[idx]
	var base: Dictionary = _base_poses[idx] if idx < _base_poses.size() else {"pos": Vector2.ZERO, "rot": 0.0}
	var local_target: Vector2 = base["pos"]
	var rot: float = base["rot"]
	# 先把 top_level 全局坐标对齐，再关掉 top_level 用本地 tween
	var global_target := global_position + local_target
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "global_position", global_target, TWEEN_SEC).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation_degrees", rot, TWEEN_SEC)
	tw.tween_property(card, "scale", Vector2.ONE, TWEEN_SEC)
	tw.chain().tween_callback(func() -> void:
		card.set_as_top_level(false)
		card.position = local_target
		card.rotation_degrees = rot
		card.scale = Vector2.ONE
		_dragging = false
		_drag_index = -1
		_press_index = -1
		_busy = false
		set_process_input(false)
		_relayout(true)
	)


func _cancel_press_state(force_snap: bool) -> void:
	_long_press_timer.stop()
	_hide_detail()
	if _dragging and force_snap:
		_snap_back_drag()
		return
	if _dragging and _drag_index >= 0 and _drag_index < _cards.size():
		var card := _cards[_drag_index]
		card.set_as_top_level(false)
	_dragging = false
	_drag_index = -1
	_press_index = -1
	_busy = false
	set_process_input(false)
