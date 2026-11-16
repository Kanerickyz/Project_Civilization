class_name ActionHandFan
extends Control
## 底栏扇形/横向重叠长方形手牌（杀戮尖塔 / 小丑牌风格）。


signal card_pressed(index: int)

const CARD_W := 72.0
const CARD_H := 100.0
const OVERLAP := 38.0
const FAN_MAX_DEG := 10.0
const LIFT_Y := -28.0
const HOVER_SCALE := 1.18

var _cards: Array[Control] = []
var _base_poses: Array[Dictionary] = []
var _hover_index: int = -1
var _interactive: bool = true
var _labels: Array[String] = []
var _kinds: Array[int] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(320, 118)
	resized.connect(_relayout)


func set_interactive(enabled: bool) -> void:
	_interactive = enabled
	for c in _cards:
		c.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)
		c.modulate.a = 1.0 if enabled else 0.55


func set_hand(labels: Array[String], kinds: Array[int]) -> void:
	_labels = labels.duplicate()
	_kinds = kinds.duplicate()
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_base_poses.clear()
	_hover_index = -1
	for i in _labels.size():
		var card := _make_card(_labels[i], int(_kinds[i]) if i < _kinds.size() else 0, i)
		add_child(card)
		_cards.append(card)
	_relayout()


func clear_hand() -> void:
	var empty_s: Array[String] = []
	var empty_k: Array[int] = []
	set_hand(empty_s, empty_k)


func _make_card(text: String, kind: int, index: int) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(CARD_W, CARD_H)
	panel.size = Vector2(CARD_W, CARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.focus_mode = Control.FOCUS_NONE
	panel.pivot_offset = Vector2(CARD_W * 0.5, CARD_H)

	var style := StyleBoxFlat.new()
	if kind == 1: # ATTACK
		style.bg_color = Color(0.42, 0.14, 0.16, 0.97)
		style.border_color = Color(0.85, 0.45, 0.4, 1.0)
	else:
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


func _relayout() -> void:
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
		var pos := Vector2(origin_x + step * float(i), base_y + arc_y)
		_base_poses.append({"pos": pos, "rot": rot})
		var card := _cards[i]
		card.z_index = i
		if i != _hover_index:
			card.position = pos
			card.rotation_degrees = rot
			card.scale = Vector2.ONE
	custom_minimum_size = Vector2(maxi(int(total_w) + 16, 280), 118)
	_apply_hover_visual()


func _on_card_hover(index: int) -> void:
	if not _interactive:
		return
	_hover_index = index
	_apply_hover_visual()


func _on_card_unhover(index: int) -> void:
	if _hover_index == index:
		_hover_index = -1
		_apply_hover_visual()


func _apply_hover_visual() -> void:
	for i in _cards.size():
		if i >= _base_poses.size():
			continue
		var card := _cards[i]
		var base: Dictionary = _base_poses[i]
		var pos: Vector2 = base["pos"]
		var rot: float = base["rot"]
		if i == _hover_index:
			card.z_index = 100
			card.position = pos + Vector2(0, LIFT_Y)
			card.rotation_degrees = rot * 0.25
			card.scale = Vector2(HOVER_SCALE, HOVER_SCALE)
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
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			card_pressed.emit(index)
			accept_event()
