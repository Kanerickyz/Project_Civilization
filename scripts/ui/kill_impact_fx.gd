extends Control
## 击杀全屏打击感：红斜横带 + 中央被击杀单位黑剪影，短暂闪现。
## 纯 2D `_draw` / CanvasItem，无 Light2D/3D。

const BAND_COLOR := Color(0.90, 0.06, 0.10, 1.0)
const SILHOUETTE_COLOR := Color(0.02, 0.02, 0.03, 1.0)
const POP_SEC := 0.05
const HOLD_SEC := 0.16
const FADE_SEC := 0.22
## 横带相对水平倾角（度，左高右低）。
const BAND_TILT_DEG := -9.0
## 横带占屏高比例（中心带）。
const BAND_HEIGHT_RATIO := 0.34
## 无棋盘尺寸时：剪影相对横带高度的回退占比（刻意偏小，避免再次盖满）。
const SILHOUETTE_BAND_FILL_FALLBACK := 0.28
## 冲击微冲倍率（只改绘制尺寸，不缩放整个 Control，避免亚像素模糊）。
const PUNCH_START := 1.12

var _tween: Tween
var _silhouette_tex: Texture2D
## 与棋盘单位屏幕尺寸对齐；为零则走横带回退。
var _silhouette_screen_size: Vector2 = Vector2.ZERO
var _punch: float = 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 像素贴图：最近邻，避免线性放大/缩小起毛边。
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	modulate.a = 0.0
	visible = false
	# 盖住棋盘与 HUD 读数，但仍低于终局面板（终局后不播）。
	z_index = 40
	resized.connect(queue_redraw)


## 重播：瞬显 → 微冲缩放 → 短停 → 淡出。
## silhouette_tex：被击杀单位精灵；screen_size 与棋盘单位屏幕尺寸一致；缺省贴图时画抽象冲击核。
func play(silhouette_tex: Texture2D = null, screen_size: Vector2 = Vector2.ZERO) -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_silhouette_tex = silhouette_tex
	_silhouette_screen_size = screen_size
	visible = true
	# 保持 Control.scale=1，冲击用 _punch，避免整层亚像素缩放造成锯齿/糊边。
	scale = Vector2.ONE
	pivot_offset = size * 0.5
	modulate.a = 1.0
	_punch = PUNCH_START
	queue_redraw()
	_tween = create_tween()
	_tween.tween_method(_set_punch, PUNCH_START, 1.0, POP_SEC).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	_tween.tween_interval(HOLD_SEC)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SEC).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN
	)
	_tween.finished.connect(func() -> void:
		visible = false
		scale = Vector2.ONE
		_punch = 1.0
		_silhouette_tex = null
		_silhouette_screen_size = Vector2.ZERO
	)


func is_flashing() -> bool:
	return visible and modulate.a > 0.05


func _set_punch(value: float) -> void:
	_punch = value
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	_draw_red_band(sz)
	_draw_impact_silhouette(sz)


func _draw_red_band(sz: Vector2) -> void:
	# 略倾的粗红带：上下边用阶梯锯齿近似刷痕。
	var cy := sz.y * 0.5
	var half_h := sz.y * BAND_HEIGHT_RATIO * 0.5
	var tilt := deg_to_rad(BAND_TILT_DEG)
	var slope := tan(tilt)
	var steps := 18
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := t * sz.x
		var jag_t := _jag_offset(i, 0) * (sz.y * 0.018)
		var jag_b := _jag_offset(i, 1) * (sz.y * 0.018)
		var y_mid := cy + slope * (x - sz.x * 0.5)
		top.append(Vector2(x, y_mid - half_h + jag_t))
		bot.append(Vector2(x, y_mid + half_h + jag_b))
	var poly := PackedVector2Array()
	for p in top:
		poly.append(p)
	for i in range(bot.size() - 1, -1, -1):
		poly.append(bot[i])
	draw_colored_polygon(poly, BAND_COLOR)
	# 上下边缘再叠一层更暗的细带，加重「刷痕」对比。
	var edge := Color(BAND_COLOR.r * 0.55, BAND_COLOR.g * 0.15, BAND_COLOR.b * 0.2, 0.55)
	_draw_edge_strip(top, -sz.y * 0.012, edge)
	_draw_edge_strip(bot, sz.y * 0.012, edge)


func _draw_edge_strip(edge: PackedVector2Array, outward: float, color: Color) -> void:
	if edge.size() < 2:
		return
	var poly := PackedVector2Array()
	for p in edge:
		poly.append(p)
	for i in range(edge.size() - 1, -1, -1):
		poly.append(edge[i] + Vector2(0.0, outward))
	draw_colored_polygon(poly, color)


func _jag_offset(i: int, salt: int) -> float:
	# 确定性伪随机阶梯，避免每帧抖动。
	var n := (i * 17 + salt * 31) % 7
	match n:
		0:
			return -1.4
		1:
			return -0.6
		2:
			return 0.0
		3:
			return 0.7
		4:
			return 1.3
		5:
			return -1.0
		_:
			return 0.4


func _draw_impact_silhouette(sz: Vector2) -> void:
	var c := sz * 0.5
	if _silhouette_tex != null:
		_draw_unit_silhouette(c, sz)
		return
	_draw_fallback_burst(c, sz)


## 用单位精灵乘纯黑 modulate：透明区仍透明，实体成黑剪影。
## 优先按棋盘单位屏幕尺寸绘制；像素对齐 + 最近邻，减少锯齿。
func _draw_unit_silhouette(c: Vector2, sz: Vector2) -> void:
	var tex_sz := _silhouette_tex.get_size()
	if tex_sz.x < 1.0 or tex_sz.y < 1.0:
		_draw_fallback_burst(c, sz)
		return
	var draw_sz := _resolve_silhouette_draw_size(tex_sz, sz)
	# 整像素对齐：位置与尺寸都取整，避免半像素采样起毛。
	draw_sz = Vector2(maxf(1.0, roundf(draw_sz.x)), maxf(1.0, roundf(draw_sz.y)))
	var origin := Vector2(roundf(c.x - draw_sz.x * 0.5), roundf(c.y - draw_sz.y * 0.5))
	var rect := Rect2(origin, draw_sz)
	draw_texture_rect(_silhouette_tex, rect, false, SILHOUETTE_COLOR)


func _resolve_silhouette_draw_size(tex_sz: Vector2, sz: Vector2) -> Vector2:
	var punch := maxf(_punch, 0.01)
	if _silhouette_screen_size.x > 1.0 and _silhouette_screen_size.y > 1.0:
		return _silhouette_screen_size * punch
	# 无棋盘尺寸时回退：按横带高度较小占比，避免再次盖满红带。
	var band_h := sz.y * BAND_HEIGHT_RATIO
	var target_h := band_h * SILHOUETTE_BAND_FILL_FALLBACK * punch
	var s := target_h / tex_sz.y
	var max_w := sz.x * 0.42
	if tex_sz.x * s > max_w:
		s = max_w / tex_sz.x
	return tex_sz * s


func _draw_fallback_burst(c: Vector2, sz: Vector2) -> void:
	var r := mini(sz.x, sz.y) * 0.16
	# 不规则冲击核心（星形扰动圆）。
	var core := PackedVector2Array()
	var lobes := 14
	for i in range(lobes):
		var a := TAU * float(i) / float(lobes)
		var wobble := 0.72 + 0.38 * _lobe_amp(i)
		core.append(c + Vector2(cos(a), sin(a)) * r * wobble)
	draw_colored_polygon(core, SILHOUETTE_COLOR)
	# 放射尖刺 / 碎片。
	var spikes := 11
	for i in range(spikes):
		var a := TAU * float(i) / float(spikes) + 0.17
		var len_m := r * (1.55 + 0.95 * _lobe_amp(i + 3))
		var tip := c + Vector2(cos(a), sin(a)) * len_m
		var side := r * 0.08
		var ortho := Vector2(-sin(a), cos(a)) * side
		var tri := PackedVector2Array([
			c + Vector2(cos(a), sin(a)) * r * 0.55,
			tip,
			c + Vector2(cos(a), sin(a)) * r * 0.55 + ortho,
		])
		draw_colored_polygon(tri, SILHOUETTE_COLOR)
		# 细针线加强「碎裂」感。
		var needle := c + Vector2(cos(a + 0.09), sin(a + 0.09)) * (len_m * 1.12)
		draw_line(c + Vector2(cos(a + 0.09), sin(a + 0.09)) * r * 0.4, needle, SILHOUETTE_COLOR, 2.2, true)
	# 中心再盖一小块实心，避免刺根透空。
	draw_circle(c, r * 0.42, SILHOUETTE_COLOR)


func _lobe_amp(i: int) -> float:
	var table := [0.2, 0.95, 0.35, 0.8, 0.15, 1.0, 0.45, 0.7, 0.25, 0.9, 0.55, 0.3, 0.85, 0.4]
	return float(table[i % table.size()])
