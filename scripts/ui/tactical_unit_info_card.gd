class_name TacticalUnitInfoCard
extends PanelContainer
## 长按单位信息卡（对照 project-autochess RealtimeUnitInfoCard 纸卡风格）。
## 只读、MOUSE_FILTER_IGNORE；松手/点空白由沙盘收起。


const UI_FONT := preload("res://resources/ui/ui_font.tres")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const STAT_ATTACK_TEX := preload("res://assets/autochess/sprites/paper_cutout/ui/stat_attack.png")
const STAT_HP_TEX := preload("res://assets/autochess/sprites/paper_cutout/ui/stat_hp.png")

const CARD_WIDTH := 228.0
const PORTRAIT_SIZE := Vector2(52.0, 60.0)
const STAT_ICON_SIZE := Vector2(16.0, 16.0)
const PAPER := Color(0.97, 0.92, 0.79, 0.98)
const INK := Color(0.13, 0.10, 0.08, 1.0)
const INK_SOFT := Color(0.32, 0.27, 0.21, 1.0)
const PLAYER_ACCENT := Color(0.20, 0.36, 0.78, 1.0)
const ENEMY_ACCENT := Color(0.69, 0.23, 0.20, 1.0)
const POP_IN_SEC := 0.16

var _portrait: TextureRect
var _name_label: Label
var _side_label: Label
var _atk_value: Label
var _hp_value: Label
var _range_label: Label
var _body_label: RichTextLabel
var _style: StyleBoxFlat
var _motion: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 80
	custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	_style = StyleBoxFlat.new()
	_style.bg_color = PAPER
	_style.border_color = INK
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(10)
	_style.set_content_margin_all(10.0)
	_style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	_style.shadow_size = 6
	_style.shadow_offset = Vector2(0.0, 3.0)
	add_theme_stylebox_override("panel", _style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = PORTRAIT_SIZE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_portrait)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(titles)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", UI_FONT)
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", INK)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(_name_label)

	_side_label = Label.new()
	_side_label.add_theme_font_override("font", UI_FONT)
	_side_label.add_theme_font_size_override("font_size", 12)
	_side_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(_side_label)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 6)
	stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(stats_row)

	stats_row.add_child(_make_stat_icon(STAT_ATTACK_TEX))
	_atk_value = _make_stat_value_label()
	stats_row.add_child(_atk_value)
	stats_row.add_child(_make_stat_icon(STAT_HP_TEX))
	_hp_value = _make_stat_value_label()
	stats_row.add_child(_hp_value)
	_range_label = _make_stat_value_label()
	_range_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.add_child(_range_label)

	var rule := ColorRect.new()
	rule.color = Color(INK, 0.35)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(CARD_WIDTH - 20.0, 0.0)
	_body_label.add_theme_font_override("normal_font", UI_FONT)
	_body_label.add_theme_font_size_override("normal_font_size", 13)
	_body_label.add_theme_color_override("default_color", INK)
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body_label)


func show_for_unit(unit: TacticalUnitInstance, anchor_global: Vector2, bounds: Rect2) -> void:
	if unit == null or unit.def == null:
		hide_info()
		return
	_apply_unit(unit)
	visible = true
	reset_size()
	var card_size := get_combined_minimum_size()
	if size.x > 1.0 and size.y > 1.0:
		card_size = size
	var parent_xf: Transform2D = get_parent().get_global_transform_with_canvas()
	var local_anchor: Vector2 = parent_xf.affine_inverse() * anchor_global
	var prefer_above: float = local_anchor.y - card_size.y - 12.0
	var pos := Vector2(local_anchor.x - card_size.x * 0.5, prefer_above)
	var pad := 8.0
	pos.x = clampf(pos.x, bounds.position.x + pad, bounds.end.x - card_size.x - pad)
	if prefer_above < bounds.position.y + pad:
		pos.y = minf(local_anchor.y + 16.0, bounds.end.y - card_size.y - pad)
	else:
		pos.y = clampf(pos.y, bounds.position.y + pad, bounds.end.y - card_size.y - pad)
	position = pos
	_play_pop_in()


func hide_info() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	_motion = null
	visible = false
	scale = Vector2.ONE
	modulate = Color.WHITE


func is_open() -> bool:
	return visible


func _apply_unit(unit: TacticalUnitInstance) -> void:
	var is_player := unit.faction == TacticalFactionScript.Id.PLAYER
	_name_label.text = unit.def.display_name
	_side_label.text = "我方" if is_player else "敌方"
	_side_label.add_theme_color_override("font_color", PLAYER_ACCENT if is_player else ENEMY_ACCENT)
	_style.border_color = PLAYER_ACCENT if is_player else ENEMY_ACCENT
	var tex: Texture2D = unit.def.texture_blue if is_player else unit.def.texture_red
	_portrait.texture = tex
	_portrait.visible = tex != null
	_atk_value.text = str(unit.effective_attack())
	_hp_value.text = "%d/%d" % [unit.hp, unit.effective_max_hp()]
	var range_txt: String
	if unit.def.attack_range_min > 0:
		range_txt = "射 %d–%d" % [unit.def.attack_range_min + 1, unit.def.attack_range]
	else:
		range_txt = "射 %d" % unit.def.attack_range
	if unit.armor > 0:
		_range_label.text = "移 %d · %s · 甲 %d" % [
			unit.def.move_range,
			range_txt,
			unit.armor,
		]
	elif unit.frenzy_stacks > 0:
		_range_label.text = "移 %d · %s · 狂 %d" % [
			unit.def.move_range,
			range_txt,
			unit.frenzy_stacks,
		]
	else:
		_range_label.text = "移 %d · %s" % [unit.def.move_range, range_txt]
	_body_label.clear()
	_body_label.append_text(_skills_bbcode(unit))


func _make_stat_icon(tex: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = STAT_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = tex
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_stat_value_label() -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _skills_bbcode(unit: TacticalUnitInstance) -> String:
	var lines: PackedStringArray = []
	var ab := unit.def.triggered_ability
	if ab != null:
		var title := ab.display_name if not ab.display_name.is_empty() else "被动"
		var hint := ab.rules_hint.strip_edges()
		if hint.is_empty():
			hint = "—"
		lines.append("[b]被动 · %s[/b]\n%s" % [title, hint])
	else:
		lines.append("[b]被动[/b]\n无")
	lines.append(_knockback_skill_line(unit))
	var skill := _active_skill_line(unit.def.id)
	if not skill.is_empty():
		lines.append(skill)
	else:
		lines.append("[b]主动技[/b]\n无（游侠无主动技卡）" if unit.def.id == "archer" else "[b]主动技[/b]\n无")
	return "\n\n".join(lines)


func _knockback_skill_line(unit: TacticalUnitInstance) -> String:
	if unit == null or unit.def == null:
		return "[b]普攻[/b]\n—"
	# attack_range≤1：一律近战击退；有最小射程死区：纯远程不推；否则仅邻格击退。
	if unit.def.attack_range <= 1:
		return (
			"[b]普攻 · 击退[/b]\n近战命中后沿攻击方向击退 1 格（短 Tween）。"
			+ "落点不可走：本次伤害改为最终伤害×1.2（向上取整）。"
			+ "落点有单位：对其额外 1 点伤害。"
		)
	if unit.def.attack_range_min >= 1:
		return "[b]普攻[/b]\n远程攻击：命中不击退。"
	return (
		"[b]普攻 · 击退（仅邻格）[/b]\n邻格命中后沿攻击方向击退 1 格；远程命中不推。"
		+ "落点不可走：本次伤害改为最终伤害×1.2（向上取整）。"
		+ "落点有单位：对其额外 1 点伤害。"
	)


func _active_skill_line(unit_id: String) -> String:
	match unit_id:
		"wardrum":
			return (
				"[b]主动技 · 鸣鼓换手[/b]\n拖到棋盘任意有效格：弃光手牌再抽 5。\n\n"
				+ "[b]主动技 · 鼓舞[/b]\n只能拖到鼓手：周围 1 格其他友方各 +1 狂暴（战局永久，上限 15；每层伤害 ×1.2 向上取整）。"
			)
		"knight":
			return (
				"[b]主动技 · 护甲[/b]\n通用卡：拖到任意己方；立刻 +2 护甲（可叠加）。伤害先打护甲，溢出不穿血。\n\n"
				+ "[b]主动技 · 冲撞[/b]\n短按或拖棋盘打出：再点方向格；朝该向最多 3 格。"
				+ "路径单位（含友军）受当前攻击力并撞开；遇不可走则停前一格且自伤 3。"
			)
		"mini_pekka":
			return "[b]主动技 · 加强攻击[/b]\n通用卡：拖到任意己方；本次攻击额外 +2 伤害。"
		"boomling":
			return "[b]主动技 · 燃爆[/b]\n只能拖到爆爆：普攻时对目标及周围施加 3 层燃烧。"
		"assassin":
			return (
				"[b]移动 · 瞬移[/b]\n移距内切比雪夫瞬移，无视中间阻挡。\n\n"
				+ "[b]主动技 · 隐身[/b]\n只能拖到刺客：再点任意存活单位令其隐身。"
			)
		"archer":
			return (
				"[b]主动技 · 万箭齐发[/b]\n只能拖到游侠：对目标格及相对攻击方向垂直左右两格造成伤害。"
			)
		_:
			return ""


func _play_pop_in() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	scale = Vector2(0.9, 0.9)
	modulate.a = 0.0
	_motion = create_tween()
	_motion.set_parallel(true)
	_motion.tween_property(self, "scale", Vector2.ONE, POP_IN_SEC).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	_motion.tween_property(self, "modulate:a", 1.0, POP_IN_SEC * 0.7)
