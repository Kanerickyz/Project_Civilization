extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main/main_menu.tscn"
const BOARD_CONFIG_PATH := "res://resources/map/board_config.tres"
const TurnClockScript := preload("res://scripts/core/turn_clock.gd")
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")
const GridBoardViewScript := preload("res://scripts/map/grid_board_view.gd")
const BoardConfigScript := preload("res://scripts/map/board_config.gd")
const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalEnemyAiScript := preload("res://scripts/units/tactical_enemy_ai.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCardDeckScript := preload("res://scripts/cards/tactical_card_deck.gd")
const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")
const ActionHandFanScript := preload("res://scripts/ui/action_hand_fan.gd")
const TacticalUnitInfoCardScript := preload("res://scripts/ui/tactical_unit_info_card.gd")
const KillImpactFxScript := preload("res://scripts/ui/kill_impact_fx.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")

enum PendingKind { NONE, MOVE, ATTACK, STEALTH }

var _clock: TurnClock
var _turn_label: Label
var _hint_label: Label
var _unit_panel: Label
var _end_turn_button: Button
var _cancel_target_button: Button
var _board_config: BoardConfig
var _board_view: GridBoardView
var _board: TacticalBoard
var _deck: TacticalCardDeck
var _selected_unit: TacticalUnitInstance
var _focus_unit: TacticalUnitInstance
var _pending_kind: PendingKind = PendingKind.NONE
var _hand_fan: ActionHandFan
var _last_log: String = ""
var _input_locked: bool = false
var _game_over: bool = false
var _turn_banner_panel: PanelContainer
var _turn_banner: Label
var _game_over_panel: PanelContainer
var _game_over_title: Label
var _top_bar: MarginContainer
var _side_panel: PanelContainer
var _bottom_bar: MarginContainer
var _unit_info_card: TacticalUnitInfoCard
var _confirm_deploy_button: Button
var _kill_impact: Control
## 开战前部署：确认前不抽手牌、不开战触发。
var _in_deployment: bool = true


func _ready() -> void:
	UiThemeScript.apply(self)
	_clock = TurnClockScript.new()
	_board_config = _load_board_config()
	_board = TacticalSandboxRosterScript.build_board_for_config(_board_config)
	_board.changed.connect(_on_board_changed)
	_deck = TacticalCardDeckScript.new()
	_deck.build_from_living_player_units(_board)
	_board.player_deck = _deck
	_build()
	# HUD 建好后再听牌库变化，避免 _ready 早期 changed 打到空 Label。
	_deck.changed.connect(_on_deck_changed)
	_enter_deployment_phase()
	_refresh_all()
	_show_deploy_banner()


func _enter_deployment_phase() -> void:
	_in_deployment = true
	_pending_kind = PendingKind.NONE
	_focus_unit = null
	_selected_unit = null
	_last_log = "部署：拖己方到左半盘 · 点「开始战斗」开战"
	_apply_deploy_mode_to_board()
	_sync_deploy_action_buttons()


func _begin_battle_after_deploy() -> void:
	if not _in_deployment:
		return
	_in_deployment = false
	if _board_view != null:
		_board_view.set_deploy_mode(false)
	_sync_deploy_action_buttons()
	_layout_hud_for_viewport()
	_fire_battle_start_triggers()
	_board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	await _apply_side_turn_start_triggers(TacticalFactionScript.Id.PLAYER)
	_deck.begin_player_turn()
	_last_log = "战斗开始 · 已抽手牌"
	_refresh_all()
	_show_turn_banner()


## GUI / 验收：跳过部署直接开战（若已开战则无操作）。
func capture_confirm_deploy() -> void:
	_begin_battle_after_deploy()


func _apply_deploy_mode_to_board() -> void:
	if _board_view == null or _board == null:
		return
	var cells: Array = _board.player_deploy_cells()
	_board_view.set_deploy_mode(_in_deployment, cells)


func _sync_deploy_action_buttons() -> void:
	if _confirm_deploy_button != null:
		_confirm_deploy_button.visible = _in_deployment
	if _end_turn_button != null:
		_end_turn_button.visible = not _in_deployment
	if _cancel_target_button != null:
		_cancel_target_button.visible = not _in_deployment
	if _hand_fan != null:
		_hand_fan.visible = not _in_deployment


func _show_deploy_banner() -> void:
	_turn_banner.text = "部署阶段 · 左半盘站位"
	_turn_banner_panel.modulate.a = 1.0
	_turn_banner_panel.scale = Vector2(0.94, 0.94)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_turn_banner_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(_turn_banner_panel, "modulate:a", 0.0, 0.55).set_delay(0.75)


func _load_board_config() -> BoardConfig:
	var loaded := load(BOARD_CONFIG_PATH)
	if loaded is BoardConfig:
		return (loaded as BoardConfig).duplicate(true) as BoardConfig
	push_warning("Sandbox: missing %s, using defaults" % BOARD_CONFIG_PATH)
	return BoardConfigScript.new()


func _fire_battle_start_triggers() -> void:
	var logs := TacticalAbilitySystemScript.process_battle_start(_board)
	if logs.size() > 0:
		_last_log = logs[logs.size() - 1]


func _apply_side_turn_start_triggers(faction: TacticalFaction.Id) -> void:
	# 燃烧（仅本方）→ 段开始被动 → 意图/出牌。
	var tick_events: Array[Dictionary] = []
	tick_events.append_array(_board.process_burn_ticks(faction))
	var killed_now: Array[TacticalUnitInstance] = []
	for ev in tick_events:
		var log_line := str(ev.get("log", ""))
		if log_line != "":
			_last_log = log_line
		var unit := ev.get("unit") as TacticalUnitInstance
		var cell: Vector2i = ev.get("cell", Vector2i.ZERO)
		var dmg := int(ev.get("damage", 0))
		if unit == null or dmg <= 0:
			continue
		# 与普攻受击同一套飘字 + 闪白。
		_board_view.play_damage_popup(cell, dmg)
		_board_view.play_unit_hit(unit)
		if bool(ev.get("killed", false)):
			killed_now.append(unit)
			_purge_dead_unit_cards(unit)
	# 段开始伤可本 tick 新杀；on_player_unit_died 幂等，旧尸体再扫也不减 MOVE。
	for u in _board.units:
		if not u.is_alive():
			_purge_dead_unit_cards(u)
	if tick_events.size() > 0:
		_refresh_all()
		# 给飘字一拍可见窗口，再让本方单位执行意图/出牌。
		await get_tree().create_timer(0.38).timeout
		for dead in killed_now:
			_board_view.play_unit_death(dead)
			_play_kill_impact()
			if _selected_unit == dead:
				_selected_unit = null
			if _focus_unit == dead:
				_focus_unit = null
				_pending_kind = PendingKind.NONE
		if killed_now.size() > 0:
			await get_tree().create_timer(0.22).timeout
			if _check_victory():
				return
	var logs := TacticalAbilitySystemScript.process_side_turn_start(_board, faction)
	if logs.size() > 0:
		_last_log = logs[logs.size() - 1]


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("121820")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_board_view = GridBoardViewScript.new()
	_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_board_view)
	_board_view.setup(_board_config)
	_board_view.set_terrain_cells(_board.terrain_cells())
	_board_view.cell_clicked.connect(_on_cell_clicked)
	_board_view.unit_long_pressed.connect(_on_unit_long_pressed)
	_board_view.unit_info_closed.connect(_hide_unit_info_card)
	_board_view.unit_deploy_dropped.connect(_on_unit_deploy_dropped)

	_unit_info_card = TacticalUnitInfoCardScript.new()
	_unit_info_card.name = "UnitInfoCard"
	add_child(_unit_info_card)

	_top_bar = MarginContainer.new()
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_top_bar.add_theme_constant_override("margin_left", 10)
	_top_bar.add_theme_constant_override("margin_top", 6)
	_top_bar.add_theme_constant_override("margin_right", 10)
	_top_bar.add_theme_constant_override("margin_bottom", 0)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_bar)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(top_row)

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 16)
	_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(_turn_label)

	_hint_label = Label.new()
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color("c5d0dc"))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_row.add_child(_hint_label)

	_side_panel = PanelContainer.new()
	# 纯展示：勿 STOP，否则竖屏顶条/横屏右侧条会吞掉下层棋盘点选。
	_side_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_side_panel)

	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 6)
	side_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_panel.add_child(side_box)

	_unit_panel = Label.new()
	_unit_panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_panel.custom_minimum_size = Vector2(150, 0)
	_unit_panel.add_theme_font_size_override("font_size", 13)
	_unit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side_box.add_child(_unit_panel)

	_bottom_bar = MarginContainer.new()
	_bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom_bar.add_theme_constant_override("margin_left", 8)
	_bottom_bar.add_theme_constant_override("margin_top", 0)
	_bottom_bar.add_theme_constant_override("margin_right", 8)
	_bottom_bar.add_theme_constant_override("margin_bottom", 4)
	# 仅底栏自身响应；空白区不挡棋盘——子控件（手牌/按钮）自己 STOP。
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_bottom_bar)

	var bottom_col := VBoxContainer.new()
	bottom_col.add_theme_constant_override("separation", 2)
	bottom_col.mouse_filter = Control.MOUSE_FILTER_PASS
	_bottom_bar.add_child(bottom_col)

	_hand_fan = ActionHandFanScript.new()
	_hand_fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_fan.custom_minimum_size = Vector2(0, 118)
	_hand_fan.card_dropped.connect(_on_hand_card_dropped)
	_hand_fan.card_drag_moved.connect(_on_hand_card_drag_moved)
	_hand_fan.card_activated.connect(_on_hand_card_activated)
	bottom_col.add_child(_hand_fan)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_col.add_child(actions)

	_confirm_deploy_button = Button.new()
	_confirm_deploy_button.text = "开始战斗"
	_confirm_deploy_button.custom_minimum_size = Vector2(112, 32)
	_confirm_deploy_button.pressed.connect(_on_confirm_deploy_pressed)
	actions.add_child(_confirm_deploy_button)

	_end_turn_button = Button.new()
	_end_turn_button.text = "结束行动"
	_end_turn_button.custom_minimum_size = Vector2(96, 32)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	actions.add_child(_end_turn_button)

	_cancel_target_button = Button.new()
	_cancel_target_button.text = "取消目标"
	_cancel_target_button.custom_minimum_size = Vector2(96, 32)
	_cancel_target_button.pressed.connect(_on_cancel_target_pressed)
	actions.add_child(_cancel_target_button)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 32)
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)

	_turn_banner_panel = PanelContainer.new()
	_turn_banner_panel.anchor_left = 0.0
	_turn_banner_panel.anchor_right = 1.0
	_turn_banner_panel.anchor_top = 0.36
	_turn_banner_panel.anchor_bottom = 0.36
	_turn_banner_panel.offset_left = 28.0
	_turn_banner_panel.offset_right = -28.0
	_turn_banner_panel.offset_top = -22.0
	_turn_banner_panel.offset_bottom = 22.0
	_turn_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_banner_panel.modulate.a = 0.0
	var banner_bg := StyleBoxFlat.new()
	banner_bg.bg_color = Color(0.04, 0.06, 0.1, 0.82)
	banner_bg.set_corner_radius_all(6)
	banner_bg.content_margin_left = 20.0
	banner_bg.content_margin_right = 20.0
	banner_bg.content_margin_top = 10.0
	banner_bg.content_margin_bottom = 10.0
	_turn_banner_panel.add_theme_stylebox_override("panel", banner_bg)
	add_child(_turn_banner_panel)

	_turn_banner = Label.new()
	_turn_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_turn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_banner.add_theme_font_size_override("font_size", 22)
	_turn_banner.add_theme_color_override("font_color", Color("f2f6fc"))
	_turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_banner_panel.add_child(_turn_banner)

	_kill_impact = KillImpactFxScript.new()
	_kill_impact.name = "KillImpactFx"
	add_child(_kill_impact)

	_game_over_panel = PanelContainer.new()
	_game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_over_panel.offset_left = -140.0
	_game_over_panel.offset_top = -72.0
	_game_over_panel.offset_right = 140.0
	_game_over_panel.offset_bottom = 72.0
	_game_over_panel.visible = false
	_game_over_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_panel.z_index = 50
	add_child(_game_over_panel)

	var go_box := VBoxContainer.new()
	go_box.add_theme_constant_override("separation", 10)
	_game_over_panel.add_child(go_box)

	_game_over_title = Label.new()
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_title.add_theme_font_size_override("font_size", 20)
	go_box.add_child(_game_over_title)

	var go_menu := Button.new()
	go_menu.text = "返回主菜单"
	go_menu.custom_minimum_size = Vector2(160, 36)
	go_menu.pressed.connect(_on_back_pressed)
	go_box.add_child(go_menu)

	resized.connect(_on_sandbox_resized)
	_layout_hud_for_viewport()


func _on_sandbox_resized() -> void:
	_layout_hud_for_viewport()


## 竖屏（高>宽）把单位条收成顶栏下短条，底栏手牌收紧；棋盘视口避开 HUD，勿挡可点格。
func _layout_hud_for_viewport() -> void:
	if _side_panel == null or _bottom_bar == null or _hand_fan == null or _board_view == null:
		return
	var portrait := size.y > size.x
	if portrait:
		_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_side_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_side_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_side_panel.offset_left = 8.0
		_side_panel.offset_top = 34.0
		_side_panel.offset_right = -8.0
		_side_panel.offset_bottom = 118.0
		_unit_panel.custom_minimum_size = Vector2(0, 0)
		_unit_panel.add_theme_font_size_override("font_size", 12)
		_hand_fan.custom_minimum_size = Vector2(0, 108)
		_bottom_bar.add_theme_constant_override("margin_bottom", 6)
		_end_turn_button.custom_minimum_size = Vector2(88, 30)
		_cancel_target_button.custom_minimum_size = Vector2(88, 30)
		if _confirm_deploy_button != null:
			_confirm_deploy_button.custom_minimum_size = Vector2(104, 30)
		_turn_banner_panel.anchor_top = 0.28
		_turn_banner_panel.anchor_bottom = 0.28
		# 顶条 + 底栏（手牌+按钮）留白，棋盘只占中间可点区。
		_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_board_view.offset_top = 122.0
		_board_view.offset_bottom = -156.0 if not _in_deployment else -56.0
		_board_view.recenter_camera()
	else:
		_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_side_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		_side_panel.offset_left = -168.0
		_side_panel.offset_top = -120.0
		_side_panel.offset_right = -8.0
		_side_panel.offset_bottom = 120.0
		_unit_panel.custom_minimum_size = Vector2(150, 0)
		_unit_panel.add_theme_font_size_override("font_size", 13)
		_hand_fan.custom_minimum_size = Vector2(0, 118)
		_bottom_bar.add_theme_constant_override("margin_bottom", 4)
		_end_turn_button.custom_minimum_size = Vector2(96, 32)
		_cancel_target_button.custom_minimum_size = Vector2(96, 32)
		if _confirm_deploy_button != null:
			_confirm_deploy_button.custom_minimum_size = Vector2(112, 32)
		_turn_banner_panel.anchor_top = 0.36
		_turn_banner_panel.anchor_bottom = 0.36
		_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_board_view.offset_top = 0.0
		_board_view.offset_bottom = -140.0 if not _in_deployment else -56.0
		_board_view.recenter_camera()


func _on_board_changed() -> void:
	if not _input_locked:
		_refresh_all()


func _on_deck_changed() -> void:
	if not _input_locked:
		_refresh_hand_ui()
		_refresh_all()


func _clear_pending_target(keep_move_focus: bool = true) -> void:
	_pending_kind = PendingKind.NONE
	# 取消瞄准：已打牌不回手，清空该单位全部攻击授权（含连拖叠加）。
	if _focus_unit != null and _deck.is_attack_authorized(_focus_unit):
		_deck.clear_attack_authorization(_focus_unit)
	else:
		_deck.pending_attack_bonus = 0
	if not keep_move_focus:
		_focus_unit = null
	elif _focus_unit != null and _focus_unit.is_alive() and _focus_unit.remaining_move_budget > 0:
		_pending_kind = PendingKind.MOVE
	else:
		_focus_unit = null


func _refresh_all() -> void:
	if _in_deployment:
		_turn_label.text = "对战 · 部署阶段"
	else:
		_turn_label.text = "对战 · %s" % _clock.status_text()
	_hint_label.text = _compose_hint()
	_refresh_unit_panel()
	_refresh_action_buttons()
	_refresh_hand_ui()
	_sync_deploy_action_buttons()
	var move_cells: Array = []
	var attack_cells: Array = []
	var sel_cell := Vector2i(-1, -1)
	var intent_preview: Dictionary = {}
	var intent_unit: TacticalUnitInstance = null
	if _in_deployment:
		move_cells = _board.player_deploy_cells()
		if _selected_unit != null and _selected_unit.is_alive():
			sel_cell = _selected_unit.cell
	elif (
		_focus_unit != null
		and _focus_unit.is_alive()
		and _clock.player_active
		and not _game_over
	):
		sel_cell = _focus_unit.cell
		if _pending_kind == PendingKind.MOVE:
			move_cells = _board.reachable_move_cells(_focus_unit)
		elif _pending_kind == PendingKind.ATTACK:
			attack_cells = _board.attack_range_cells(_focus_unit)
	elif _selected_unit != null and _selected_unit.is_alive():
		sel_cell = _selected_unit.cell
		# 敌方狼骑兵：点选即展示当前可行动邻域（绿=移动可达≤MOVE_STEP_CAP，红=攻击射程）
		# + 下一回合意图虚影（路径/目标/回血加攻提示）。
		if TacticalEnemyAiScript.uses_behavior_sm(_selected_unit):
			move_cells = _board.preview_reachable_move_cells(
				_selected_unit, TacticalEnemyAiScript.MOVE_STEP_CAP
			)
			attack_cells = _board.attack_range_cells(_selected_unit)
			intent_preview = TacticalEnemyAiScript.preview_next_action(_board, _selected_unit)
			intent_unit = _selected_unit
	_board_view.sync_tactical_units(
		_board.living_units(),
		sel_cell,
		move_cells,
		attack_cells,
		_board.ignited_cells_for_view(),
		intent_preview,
		intent_unit
	)


func _compose_hint() -> String:
	if _in_deployment:
		if _last_log != "":
			return _last_log
		return "部署：拖己方到左半盘 · 「开始战斗」"
	if _pending_kind == PendingKind.MOVE and _focus_unit != null:
		return "移动中：%s · 点绿格（余移力 %d）" % [
			_focus_unit.def.display_name,
			_focus_unit.remaining_move_budget,
		]
	if _pending_kind == PendingKind.ATTACK and _focus_unit != null:
		var left := _deck.attack_authorization_count(_focus_unit)
		if left > 1:
			return "攻击中：%s · 点红圈内单位（余 %d 次）" % [_focus_unit.def.display_name, left]
		return "攻击中：%s · 点红圈内单位" % _focus_unit.def.display_name
	if _pending_kind == PendingKind.STEALTH and _focus_unit != null:
		return "隐身：%s · 点任意存活单位" % _focus_unit.def.display_name
	if _last_log != "":
		return _last_log
	return "点己方移动 · 通用卡拖单位 · 技能卡短按/拖棋盘 · 库 %d · 弃 %d" % [
		_deck.draw_pile.size(),
		_deck.discard_pile.size(),
	]


func _refresh_action_buttons() -> void:
	if _confirm_deploy_button != null:
		_confirm_deploy_button.disabled = not _in_deployment or _input_locked or _game_over
	var player_turn := _clock.player_active and not _game_over and not _in_deployment
	_end_turn_button.disabled = not player_turn or _input_locked
	_cancel_target_button.disabled = (
		not player_turn or _input_locked or _pending_kind == PendingKind.NONE
	)


func _refresh_unit_panel() -> void:
	var u := _focus_unit if _focus_unit != null else _selected_unit
	if u == null or not u.is_alive():
		_unit_panel.text = "未选中单位\n（点己方移动 / 拖攻击卡）"
		return
	var ab := u.def.triggered_ability
	var skill_line := ab.display_name if ab != null else "—"
	var skill_rules := ab.rules_hint if ab != null else ""
	var move_line := "移力 %d/%d" % [u.remaining_move_budget, u.def.action_move_budget()]
	var status_extra := ""
	if u.armor > 0:
		status_extra += "\n护甲 %d" % u.armor
	if u.burn_stacks > 0:
		status_extra += "\n燃烧 %d 层" % u.burn_stacks
	if u.frenzy_stacks > 0:
		status_extra += "\n狂暴 %d 层" % u.frenzy_stacks
	if u.is_stealthed():
		status_extra += "\n隐身"
	if u.def.teleports:
		status_extra += "\n瞬移"
	var range_line: String
	if u.def.attack_range_min > 0:
		range_line = "射程 %d–%d（禁≤%d）" % [
			u.def.attack_range_min + 1,
			u.def.attack_range,
			u.def.attack_range_min,
		]
	else:
		range_line = "射程 %d" % u.def.attack_range
	_unit_panel.text = (
		"%s · %s\nHP %d/%d · 攻 %d · %s · %s%s\n%s\n%s"
		% [
			u.def.display_name,
			TacticalFactionScript.label(u.faction),
			u.hp,
			u.effective_max_hp(),
			u.effective_attack(),
			move_line,
			range_line,
			status_extra,
			skill_line,
			skill_rules,
		]
	)


func _refresh_hand_ui() -> void:
	if _hand_fan == null:
		return
	if _in_deployment:
		_hand_fan.set_hand([], [], [])
		_hand_fan.set_interactive(false)
		return
	var labels: Array[String] = []
	var kinds: Array[int] = []
	var details: Array[String] = []
	for card in _deck.hand:
		labels.append(card.display_label())
		kinds.append(int(card.kind))
		details.append(card.rules_detail())
	_hand_fan.set_hand(labels, kinds, details)
	var player_turn := (
		_clock.player_active and not _game_over and not _input_locked and not _in_deployment
	)
	_hand_fan.set_interactive(player_turn)


func _show_turn_banner() -> void:
	if _game_over:
		return
	_turn_banner.text = _clock.status_text()
	_turn_banner_panel.modulate.a = 1.0
	_turn_banner_panel.scale = Vector2(0.94, 0.94)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_turn_banner_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(_turn_banner_panel, "modulate:a", 0.0, 0.55).set_delay(0.75)


func _on_confirm_deploy_pressed() -> void:
	if not _in_deployment or _input_locked or _game_over:
		return
	_begin_battle_after_deploy()


func _on_unit_deploy_dropped(unit: TacticalUnitInstance, cell: Vector2i) -> void:
	if not _in_deployment or _input_locked or _game_over:
		if unit != null and _board_view != null:
			_board_view.cancel_deploy_drag_visual(unit)
		return
	if unit == null or unit.faction != TacticalFactionScript.Id.PLAYER:
		_last_log = "只能拖动己方单位"
		if unit != null and _board_view != null:
			_board_view.cancel_deploy_drag_visual(unit)
		_refresh_all()
		return
	var from := unit.cell
	if _board.try_deploy_place(unit, cell):
		_selected_unit = unit
		if _board_view != null:
			_board_view.accept_deploy_placement(unit, from)
		_last_log = "%s 部署至 (%d,%d)" % [unit.def.display_name, cell.x, cell.y]
	else:
		if _board_view != null:
			_board_view.cancel_deploy_drag_visual(unit)
		_last_log = "只能放到左半盘空格或与己方换位"
	_refresh_all()


## 拖牌跟手：高亮当前格；悬停单位播选中脉冲（可落/不可落不同态）。
func _on_hand_card_drag_moved(index: int, global_pos: Vector2) -> void:
	if _board_view == null:
		return
	if _in_deployment or _input_locked or _game_over or not _clock.player_active:
		_board_view.clear_card_drag_hover()
		return
	if index < 0 or index >= _deck.hand.size():
		_board_view.clear_card_drag_hover()
		return
	var peek: TacticalActionCard = _deck.hand[index]
	var cell_v: Variant = _board_view.pick_cell_at_global(global_pos)
	if cell_v == null:
		_board_view.clear_card_drag_hover()
		# 拖出棋盘仍保留可释放格高亮（无箭头）。
		if peek != null and peek.plays_on_board():
			_board_view.set_skill_drag_preview(
				null, null, peek.release_preview_cells(_board), false
			)
		return
	var cell: Vector2i = cell_v
	var unit := _board.unit_at(cell)
	var hover_unit: TacticalUnitInstance = null
	var valid := false
	if peek != null and peek.plays_on_board():
		var release_cells: Array[Vector2i] = peek.release_preview_cells(_board)
		var in_release := cell in release_cells
		# 自由打出：棋盘任意有效格可松手；高亮按技能规则格。
		valid = true
		if unit != null and unit.is_alive():
			hover_unit = unit
		var caster := peek.find_bound_caster(_board)
		_board_view.set_card_drag_hover(cell, hover_unit, valid)
		if caster != null:
			_board_view.set_skill_drag_preview(caster.cell, cell, release_cells, in_release)
		else:
			_board_view.set_skill_drag_preview(null, null, release_cells, false)
		return
	elif unit != null and unit.is_alive():
		hover_unit = unit
		valid = (
			unit.faction == TacticalFactionScript.Id.PLAYER
			and peek != null
			and peek.can_drop_on(unit)
		)
	_board_view.clear_skill_drag_preview()
	_board_view.set_card_drag_hover(cell, hover_unit, valid)


## 短按：非通用技自由打出；通用卡短按无效。
func _on_hand_card_activated(index: int) -> void:
	if _in_deployment or _input_locked or _game_over or not _clock.player_active:
		return
	if index < 0 or index >= _deck.hand.size():
		return
	var peek: TacticalActionCard = _deck.hand[index]
	if peek == null or not peek.plays_on_board():
		return
	_resolve_free_skill_play(index)


## 单位目标卡拖到己方单位；非通用技松手在棋盘/手牌区即可。无效回手。
func _on_hand_card_dropped(index: int, global_pos: Vector2) -> void:
	if _board_view != null:
		_board_view.clear_card_drag_hover()
	if _in_deployment or _input_locked or _game_over or not _clock.player_active:
		_hand_fan.notify_drop_resolved(false)
		return
	if index < 0 or index >= _deck.hand.size():
		_hand_fan.notify_drop_resolved(false)
		return
	var peek: TacticalActionCard = _deck.hand[index]
	var cell_v: Variant = _board_view.pick_cell_at_global(global_pos)
	# 非通用技：棋盘格或手牌区（无格）均可打出。
	if peek != null and peek.plays_on_board():
		if peek.find_bound_caster(_board) == null:
			_last_log = "施法者不在场 · 卡已回手"
			_hand_fan.notify_drop_resolved(false)
			_refresh_all()
			return
		_hand_fan.notify_drop_resolved(true)
		_resolve_free_skill_play(index)
		return
	if cell_v == null:
		_last_log = "未落到单位上 · 卡已回手"
		_hand_fan.notify_drop_resolved(false)
		_refresh_all()
		return
	var cell: Vector2i = cell_v
	var target := _board.unit_at(cell)
	if target == null or target.faction != TacticalFactionScript.Id.PLAYER:
		_last_log = "需拖到己方单位 · 卡已回手"
		_hand_fan.notify_drop_resolved(false)
		_refresh_all()
		return
	if peek != null and not peek.can_drop_on(target):
		_last_log = "该卡须拖到对应角色 · 卡已回手"
		_hand_fan.notify_drop_resolved(false)
		_refresh_all()
		return
	# 先结束拖态，再从手牌结算进弃，避免重建打断回弹。
	_hand_fan.notify_drop_resolved(true)
	var card := _deck.play_hand_index(index)
	if card == null or not card.is_valid():
		_last_log = "无法使用该卡"
		_refresh_all()
		return
	_apply_unit_targeted_card(card, target)


## 非通用绑角色技：自动找施法者结算。
func _resolve_free_skill_play(index: int) -> void:
	if index < 0 or index >= _deck.hand.size():
		return
	var peek: TacticalActionCard = _deck.hand[index]
	if peek == null or not peek.plays_on_board():
		return
	var caster := peek.find_bound_caster(_board)
	if caster == null:
		_last_log = "施法者不在场 · 卡已回手"
		_refresh_all()
		return
	var card := _deck.play_hand_index(index)
	if card == null or not card.is_valid():
		_last_log = "无法使用该卡"
		_refresh_all()
		return
	if card.kind == TacticalActionCardScript.Kind.SKILL_DRAW:
		_pending_kind = PendingKind.NONE
		_focus_unit = null
		_selected_unit = null
		var drawn := _deck.resolve_wardrum_redraw()
		_last_log = "鸣鼓换手：弃手后抽 %d 张" % drawn
		_refresh_all()
		_maybe_auto_end_player_turn_if_hand_empty()
		return
	_apply_unit_targeted_card(card, caster)


func _apply_unit_targeted_card(card: TacticalActionCard, target: TacticalUnitInstance) -> void:
	_focus_unit = target
	_selected_unit = target
	if card.kind == TacticalActionCardScript.Kind.MOVE:
		# 移动已改为点格移力池；遗留移动卡打出无效。
		_pending_kind = PendingKind.NONE
		_select_player_for_move(target)
		_last_log = "移动不需卡 · 点绿格即可（余移力 %d）" % target.remaining_move_budget
	elif card.kind == TacticalActionCardScript.Kind.SKILL_ARMOR:
		var grant := maxi(1, card.armor_grant)
		target.add_armor(grant)
		_pending_kind = PendingKind.NONE
		_last_log = "护甲：%s +%d（现 %d）· 伤害先打护甲，溢出不穿血" % [
			target.def.display_name,
			grant,
			target.armor,
		]
	elif card.kind == TacticalActionCardScript.Kind.SKILL_INSPIRE:
		var inspire: Dictionary = _board.apply_inspire_frenzy(target, 1)
		_pending_kind = PendingKind.NONE
		_last_log = str(inspire.get("log", "鼓舞"))
	elif card.kind == TacticalActionCardScript.Kind.SKILL_STEALTH:
		_pending_kind = PendingKind.STEALTH
		_last_log = "隐身：%s · 点任意存活单位" % target.def.display_name
	elif card.is_attack_aim():
		var is_volley := card.kind == TacticalActionCardScript.Kind.SKILL_VOLLEY
		_deck.authorize_attack(
			target, card.attack_bonus_damage, card.aoe_burn_stacks, is_volley
		)
		_pending_kind = PendingKind.ATTACK
		if card.kind == TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK:
			_last_log = "加强攻击：%s · 额外+%d · 点红圈内单位（含友方；本卡一次）" % [
				target.def.display_name,
				card.attack_bonus_damage,
			]
		elif card.kind == TacticalActionCardScript.Kind.SKILL_BURN_ATTACK:
			_last_log = "燃爆：%s · 目标及周围 +%d 燃烧 · 点红圈内单位" % [
				target.def.display_name,
				card.aoe_burn_stacks,
			]
		elif is_volley:
			_last_log = "万箭齐发：%s · 目标及攻击方向左右两格 · 点红圈内单位" % target.def.display_name
		else:
			_last_log = "攻击者：%s · 点红圈内单位（含友方；本卡一次）" % target.def.display_name
		_append_attack_card_passive_logs()
	else:
		_last_log = "未知卡类型"
		_pending_kind = PendingKind.NONE
	_refresh_all()
	# 即时卡结算后判空手；攻/隐身瞄准中会跳过，等结算完再判。
	_maybe_auto_end_player_turn_if_hand_empty()


func _on_cancel_target_pressed() -> void:
	if _in_deployment or _input_locked or _game_over or not _clock.player_active:
		return
	_last_log = "已取消瞄准（已用卡不回手）"
	_clear_pending_target(true)
	_refresh_all()
	_maybe_auto_end_player_turn_if_hand_empty()


func _on_unit_long_pressed(unit: TacticalUnitInstance, anchor_global: Vector2) -> void:
	if unit == null or _unit_info_card == null:
		return
	if _hand_fan != null and _hand_fan.is_busy():
		return
	_selected_unit = unit
	# 信息卡挂在沙盘本地坐标。
	var local_bounds := Rect2(Vector2.ZERO, size)
	_unit_info_card.show_for_unit(unit, anchor_global, local_bounds)
	_last_log = "信息卡：%s（松手关闭）" % unit.def.display_name
	_refresh_all()
	# 刷新后保持信息卡在最前。
	if _unit_info_card.get_parent() == self:
		move_child(_unit_info_card, get_child_count() - 1)


func _hide_unit_info_card() -> void:
	if _unit_info_card != null:
		_unit_info_card.hide_info()


func _on_cell_clicked(cell: Vector2i) -> void:
	if _input_locked or _game_over:
		return
	if _hand_fan != null and _hand_fan.is_busy():
		return
	_hide_unit_info_card()

	if _in_deployment:
		_on_deploy_cell_clicked(cell)
		return
	if not _clock.player_active:
		return

	var clicked := _board.unit_at(cell)

	# 移动瞄准：点选己方后点绿格；可切换到其他己方。
	if _pending_kind == PendingKind.MOVE and _focus_unit != null:
		if clicked != null:
			if clicked.faction == TacticalFactionScript.Id.PLAYER:
				_select_player_for_move(clicked)
				_refresh_all()
				return
			_last_log = "移动请点空格"
			_refresh_all()
			return
		if not _board.is_passable(cell):
			_last_log = "%s不可通行" % _board.terrain_display_name(cell)
			_refresh_all()
			return
		if _focus_unit.remaining_move_budget <= 0:
			_last_log = "%s 移力已用尽" % _focus_unit.def.display_name
			_pending_kind = PendingKind.NONE
			_refresh_all()
			return
		if _board.try_move(_focus_unit, cell):
			_last_log = "%s 移动至 (%d,%d) · 余移力 %d" % [
				_focus_unit.def.display_name,
				cell.x,
				cell.y,
				_focus_unit.remaining_move_budget,
			]
			if _focus_unit.remaining_move_budget > 0:
				_pending_kind = PendingKind.MOVE
			else:
				_pending_kind = PendingKind.NONE
			_refresh_all()
			_input_locked = true
			_refresh_action_buttons()
			await get_tree().create_timer(_board_view.unit_move_duration_sec()).timeout
			_input_locked = false
			_refresh_all()
		else:
			_last_log = "无法移动到该格"
			_refresh_all()
		return

	# 攻击瞄准：攻击者已由拖卡选定；可点红圈内任意其他单位（含友方）。
	if _pending_kind == PendingKind.ATTACK and _focus_unit != null:
		if not _deck.is_attack_authorized(_focus_unit):
			_last_log = "无攻击授权 · 请再拖一张攻击卡"
			_clear_pending_target(false)
			_refresh_all()
			return
		if clicked != null and clicked != _focus_unit:
			var atk_dist := GridMathScript.chebyshev(_focus_unit.cell, clicked.cell)
			var in_range := _focus_unit.def.is_chebyshev_in_attack_band(atk_dist)
			if in_range:
				_run_player_attack_async(cell, clicked)
				return
		_last_log = "请点红圈内单位（可友方），或取消目标"
		_refresh_all()
		return

	# 刺客隐身瞄准：点任意存活单位。
	if _pending_kind == PendingKind.STEALTH and _focus_unit != null:
		if clicked == null or not clicked.is_alive():
			_last_log = "请点存活单位令其隐身"
			_refresh_all()
			return
		var stealth_res: Dictionary = _board.apply_grant_stealth(_focus_unit, clicked)
		_pending_kind = PendingKind.NONE
		_last_log = str(stealth_res.get("log", "隐身"))
		_refresh_all()
		_maybe_auto_end_player_turn_if_hand_empty()
		return

	# 无待结算卡：点己方进入移动；点敌方查看；点空地提示。
	if clicked != null:
		_selected_unit = clicked
		if clicked.faction == TacticalFactionScript.Id.PLAYER:
			_select_player_for_move(clicked)
		elif TacticalEnemyAiScript.uses_behavior_sm(clicked):
			_focus_unit = null
			_pending_kind = PendingKind.NONE
			_last_log = "查看 %s · 绿=可移动 · 红=可攻击 · 虚影=下回合意图" % clicked.def.display_name
		else:
			_focus_unit = null
			_pending_kind = PendingKind.NONE
			_last_log = "查看 %s" % clicked.def.display_name
		_refresh_all()
		return
	if not _board.is_passable(cell):
		_last_log = "%s不可通行" % _board.terrain_display_name(cell)
	_refresh_all()


func _select_player_for_move(unit: TacticalUnitInstance) -> void:
	_selected_unit = unit
	_focus_unit = unit
	if unit.remaining_move_budget > 0:
		_pending_kind = PendingKind.MOVE
		_last_log = "已选 %s · 点绿格移动（余移力 %d）" % [
			unit.def.display_name,
			unit.remaining_move_budget,
		]
	else:
		_pending_kind = PendingKind.NONE
		_last_log = "%s 本段移力已用尽 · 攻击请拖卡" % unit.def.display_name


func _run_player_attack_async(target_cell: Vector2i, target: TacticalUnitInstance) -> void:
	if _input_locked or _focus_unit == null:
		return
	var attacker := _focus_unit
	if not _deck.is_attack_authorized(attacker):
		_last_log = "无攻击授权"
		_clear_pending_target(false)
		_refresh_all()
		return
	# 先锁输入，避免击退改格时 board.changed 提前 refresh 掐掉攻击/击退时序。
	_input_locked = true
	_refresh_action_buttons()
	var bonus := _deck.pending_attack_bonus
	var burn_stacks := _deck.pending_aoe_burn_stacks
	var volley := _deck.pending_volley
	var atk := TacticalCombatScript.try_basic_attack(
		_board,
		attacker,
		target_cell,
		TacticalFactionScript.Id.PLAYER,
		true,
		bonus,
		burn_stacks,
		volley
	)
	_last_log = atk["log"]
	if not atk["ok"]:
		_input_locked = false
		_refresh_all()
		return
	# 成功后消耗队首授权（玩家无 attacked_this_side_turn 预算）。
	_deck.consume_attack_authorization(attacker)
	var tw := _board_view.play_unit_attack(attacker, target_cell)
	if tw != null:
		await tw.finished
	await _feedback_from_attack(target, atk, target_cell)
	_pending_kind = PendingKind.NONE
	# 同单位连拖多张攻击卡：仍有余次则继续瞄准，否则若有移力则切回移动。
	if attacker.is_alive() and _deck.is_attack_authorized(attacker):
		_pending_kind = PendingKind.ATTACK
		_focus_unit = attacker
	elif attacker.is_alive() and attacker.remaining_move_budget > 0:
		_pending_kind = PendingKind.MOVE
		_focus_unit = attacker
	_check_victory()
	_input_locked = false
	_refresh_all()
	# 攻击/击杀补牌（如游侠猎获）结算完后再判空手。
	_maybe_auto_end_player_turn_if_hand_empty()


func _feedback_from_attack(
	target: TacticalUnitInstance, res: Dictionary, hit_cell: Vector2i = Vector2i(-1, -1)
) -> void:
	var dmg: int = int(res.get("damage", 0))
	var popup_cell := hit_cell
	if popup_cell.x < 0:
		var from_kb: Vector2i = res.get("knockback_from", Vector2i(-1, -1)) as Vector2i
		popup_cell = from_kb if from_kb.x >= 0 else target.cell
	_board_view.play_damage_popup(popup_cell, dmg)
	_board_view.play_unit_hit(target)
	if res.get("killed", false):
		_purge_dead_unit_cards(target)
		_board_view.play_unit_death(target)
		_play_kill_impact()
		if _selected_unit == target:
			_selected_unit = null
		if _focus_unit == target:
			_focus_unit = null
			_pending_kind = PendingKind.NONE
	var col: TacticalUnitInstance = res.get("collision_target") as TacticalUnitInstance
	var col_dmg: int = int(res.get("collision_damage", 0))
	if col != null and col_dmg > 0:
		_board_view.play_damage_popup(col.cell, col_dmg)
		_board_view.play_unit_hit(col)
		if res.get("collision_killed", false):
			_purge_dead_unit_cards(col)
			_board_view.play_unit_death(col)
			_play_kill_impact()
			if _selected_unit == col:
				_selected_unit = null
			if _focus_unit == col:
				_focus_unit = null
				_pending_kind = PendingKind.NONE
	var volley_hits: Array = res.get("volley_hits", []) as Array
	for hit in volley_hits:
		if not (hit is Dictionary):
			continue
		var vu: TacticalUnitInstance = (hit as Dictionary).get("unit") as TacticalUnitInstance
		var vcell: Vector2i = (hit as Dictionary).get("cell", Vector2i(-1, -1)) as Vector2i
		var vdmg: int = int((hit as Dictionary).get("damage", 0))
		if vu == null or vdmg <= 0:
			continue
		_board_view.play_damage_popup(vcell if vcell.x >= 0 else vu.cell, vdmg)
		_board_view.play_unit_hit(vu)
		if bool((hit as Dictionary).get("killed", false)):
			_purge_dead_unit_cards(vu)
			_board_view.play_unit_death(vu)
			_play_kill_impact()
			if _selected_unit == vu:
				_selected_unit = null
			if _focus_unit == vu:
				_focus_unit = null
				_pending_kind = PendingKind.NONE
	# 击退成功：refresh 触发从旧格到新格的位移 Tween（可见推开，禁止瞬移）。
	if res.get("knockback_moved", false) and target != null and target.is_alive():
		_refresh_all()
		await get_tree().create_timer(_board_view.unit_move_duration_sec()).timeout


func _play_kill_impact() -> void:
	if _game_over or _kill_impact == null:
		return
	if _kill_impact.has_method("play"):
		_kill_impact.call("play")


## GUI 截图：强制播一次击杀冲击（不等真实击杀结算）。
func capture_play_kill_impact() -> bool:
	if _kill_impact == null:
		return false
	_play_kill_impact()
	return _kill_impact.visible


func _purge_dead_unit_cards(unit: TacticalUnitInstance) -> void:
	if unit == null:
		return
	# 仅己方阵亡：手/库/弃减通用攻 1，并减该角色绑定主动技；敌方不影响玩家牌库。
	if unit.faction != TacticalFactionScript.Id.PLAYER:
		return
	var n := _deck.on_player_unit_died(unit)
	if n > 0:
		_last_log = "%s 阵亡，库中减去移/攻/主动技（共 %d）" % [
			unit.def.display_name if unit.def != null else "单位",
			n,
		]
		# 对手段常锁输入；deck.changed 在锁定期会跳过 UI，此处强制同步手牌。
		_refresh_hand_ui()


## 部署阶段点选：点己方选中；已选中时点绿区空格/己方则落位或换位。
func _on_deploy_cell_clicked(cell: Vector2i) -> void:
	var clicked := _board.unit_at(cell)
	if clicked != null and clicked.faction == TacticalFactionScript.Id.PLAYER:
		if (
			_selected_unit != null
			and _selected_unit != clicked
			and _selected_unit.faction == TacticalFactionScript.Id.PLAYER
		):
			if _board.try_deploy_place(_selected_unit, cell):
				_last_log = "%s 与 %s 换位" % [
					_selected_unit.def.display_name,
					clicked.def.display_name,
				]
				_refresh_all()
				return
		_selected_unit = clicked
		_last_log = "已选 %s · 拖到绿区或点绿区落位" % clicked.def.display_name
		_refresh_all()
		return
	if _selected_unit != null and _selected_unit.faction == TacticalFactionScript.Id.PLAYER:
		if _board.try_deploy_place(_selected_unit, cell):
			_last_log = "%s 部署至 (%d,%d)" % [_selected_unit.def.display_name, cell.x, cell.y]
		else:
			_last_log = "只能放到绿区空格或与己方换位"
		_refresh_all()
		return
	if clicked != null:
		_selected_unit = clicked
		_last_log = "敌方固定 · 请拖己方单位"
	else:
		_last_log = "先点选己方单位，再拖/点到绿区"
	_refresh_all()


## 手牌打完后自动结束行动。须在鸣鼓换手抽牌、游侠猎获等补牌结算之后调用；
## 攻/隐身瞄准未完成时不触发（卡已离手但仍待点目标）。
func _maybe_auto_end_player_turn_if_hand_empty() -> void:
	if _in_deployment or _input_locked or _game_over or not _clock.player_active:
		return
	if _deck == null or not _deck.hand.is_empty():
		return
	if _pending_kind == PendingKind.ATTACK or _pending_kind == PendingKind.STEALTH:
		return
	_last_log = "手牌已打完 · 自动结束行动"
	_on_end_turn_pressed()


func _on_end_turn_pressed() -> void:
	if _in_deployment or _input_locked or _game_over or not _clock.player_active:
		return
	_deck.end_player_turn()
	_pending_kind = PendingKind.NONE
	_focus_unit = null
	_clock.end_turn()
	_board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	_input_locked = true
	_refresh_action_buttons()
	await _apply_side_turn_start_triggers(TacticalFactionScript.Id.OPPONENT)
	if _game_over:
		_input_locked = false
		_refresh_all()
		return
	_selected_unit = null
	_show_turn_banner()
	_refresh_all()
	_run_opponent_turn_async()


func _run_opponent_turn_async() -> void:
	_input_locked = true
	_refresh_action_buttons()
	_refresh_hand_ui()
	await get_tree().process_frame
	var opponents := TacticalEnemyAiScript.sorted_opponents(_board)
	for unit in opponents:
		if not unit.is_alive():
			continue
		var events := TacticalEnemyAiScript.run_opponent_unit_actions(_board, unit)
		for ev in events:
			var kind: String = ev.get("kind", "")
			if kind == "move":
				var mover := ev["unit"] as TacticalUnitInstance
				_last_log = "对手 %s 移动 · 剩余移力 %d" % [
					mover.def.display_name, mover.remaining_move_budget
				]
				_refresh_all()
				await get_tree().create_timer(_board_view.unit_move_duration_sec()).timeout
			elif kind == "attack":
				var res: Dictionary = ev["result"]
				var cell: Vector2i = ev["cell"]
				var attacker := ev["unit"] as TacticalUnitInstance
				var tw := _board_view.play_unit_attack(attacker, cell)
				if tw != null:
					await tw.finished
				# 击杀后 unit_at 只返回存活单位，须用结算里保留的 target 引用。
				var target: TacticalUnitInstance = res.get("target") as TacticalUnitInstance
				if target == null:
					target = _board.unit_at(cell)
				_last_log = res.get("log", "对手攻击")
				if target != null:
					await _feedback_from_attack(target, res, cell)
					if res.get("killed", false):
						await get_tree().create_timer(0.22).timeout
				_refresh_all()
				await get_tree().create_timer(0.28).timeout
			elif kind == "heal":
				var healer := ev["unit"] as TacticalUnitInstance
				_last_log = str(ev.get("log", "对手回血"))
				_board_view.play_float_text(
					healer.cell, "+%d血" % int(ev.get("amount", 0)), Color("7dff9a")
				)
				_refresh_all()
				await get_tree().create_timer(0.28).timeout
			elif kind == "buff_atk":
				var buffer := ev["unit"] as TacticalUnitInstance
				_last_log = str(ev.get("log", "对手加攻"))
				_board_view.play_float_text(
					buffer.cell, "+%d攻" % int(ev.get("amount", 0)), Color("ffe08a")
				)
				_refresh_all()
				await get_tree().create_timer(0.28).timeout
			elif kind == "idle":
				_last_log = str(ev.get("log", "对手待机"))
				_refresh_all()
				await get_tree().create_timer(0.12).timeout
			if _check_victory():
				return
		await get_tree().create_timer(0.18).timeout

	_clock.end_turn()
	_board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	await _apply_side_turn_start_triggers(TacticalFactionScript.Id.PLAYER)
	if _game_over:
		_input_locked = false
		_refresh_all()
		return
	_deck.begin_player_turn()
	_last_log = "对手结束行动 · 已抽手牌"
	_show_turn_banner()
	_input_locked = false
	_refresh_all()


func _check_victory() -> bool:
	if _game_over:
		return true
	var player_lost := TacticalCombatScript.faction_defeated(
		_board, TacticalFactionScript.Id.PLAYER
	)
	var opp_lost := TacticalCombatScript.faction_defeated(
		_board, TacticalFactionScript.Id.OPPONENT
	)
	if not player_lost and not opp_lost:
		return false
	_game_over = true
	_input_locked = false
	_selected_unit = null
	_focus_unit = null
	_pending_kind = PendingKind.NONE
	if player_lost:
		_game_over_title.text = "失败\n对手获胜"
	else:
		_game_over_title.text = "胜利\n我方获胜"
	_game_over_panel.visible = true
	_refresh_all()
	return true


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


## GUI 验收：按 id 选中玩家单位（knight/archer/mini_pekka/wardrum）。
func capture_select_player_unit(unit_id: String) -> void:
	for u in _board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == unit_id:
			_select_player_for_move(u)
			_refresh_all()
			return


## GUI 验收：选中敌方狼骑兵并刷新行动格 + 意图虚影 overlay。
func capture_select_opponent_rider() -> bool:
	for u in _board.living_units():
		if TacticalEnemyAiScript.uses_behavior_sm(u):
			_focus_unit = null
			_pending_kind = PendingKind.NONE
			_selected_unit = u
			_last_log = "查看 %s · 绿=可移动 · 红=可攻击 · 虚影=下回合意图" % u.def.display_name
			_refresh_all()
			return true
	return false


## GUI 验收：弹出指定单位信息卡（模拟长按）。
func capture_show_unit_info(unit_id: String, prefer_player: bool = true) -> bool:
	var unit: TacticalUnitInstance = null
	for u in _board.living_units():
		if u.def.id != unit_id:
			continue
		if prefer_player and u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		if not prefer_player and u.faction != TacticalFactionScript.Id.OPPONENT:
			continue
		unit = u
		break
	if unit == null:
		for u in _board.living_units():
			if u.def.id == unit_id:
				unit = u
				break
	if unit == null or _board_view == null:
		return false
	_on_unit_long_pressed(unit, _board_view.unit_head_global_position(unit))
	return true


## GUI 证据：模拟拖牌悬停在指定己方单位上（高亮格 + 选中脉冲）。
func capture_card_drag_hover(unit_id: String, valid_drop: bool = true) -> bool:
	if _board_view == null or _board == null:
		return false
	var unit: TacticalUnitInstance = null
	for u in _board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == unit_id:
			unit = u
			break
	if unit == null:
		return false
	_board_view.set_card_drag_hover(unit.cell, unit, valid_drop)
	return true


## GUI 验收：把一手中第一张指定种类卡「拖」到指定己方单位 id 上。
## kind_name: move | attack | skill_draw | skill_strong_attack | skill_burn_attack | skill_armor | skill_inspire | skill_stealth | skill_volley
func capture_drop_first_card_on_unit(kind_name: String, unit_id: String) -> bool:
	var want := TacticalActionCardScript.Kind.MOVE
	match kind_name:
		"attack":
			want = TacticalActionCardScript.Kind.ATTACK
		"skill_draw":
			want = TacticalActionCardScript.Kind.SKILL_DRAW
		"skill_strong_attack":
			want = TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK
		"skill_burn_attack":
			want = TacticalActionCardScript.Kind.SKILL_BURN_ATTACK
		"skill_armor":
			want = TacticalActionCardScript.Kind.SKILL_ARMOR
		"skill_inspire":
			want = TacticalActionCardScript.Kind.SKILL_INSPIRE
		"skill_stealth":
			want = TacticalActionCardScript.Kind.SKILL_STEALTH
		"skill_volley":
			want = TacticalActionCardScript.Kind.SKILL_VOLLEY
		_:
			want = TacticalActionCardScript.Kind.MOVE
	var idx := -1
	for i in _deck.hand.size():
		var c: TacticalActionCard = _deck.hand[i]
		if c.kind == want:
			idx = i
			break
	if idx < 0:
		return false
	var unit: TacticalUnitInstance = null
	for u in _board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == unit_id:
			unit = u
			break
	if unit == null:
		return false
	var peek: TacticalActionCard = _deck.hand[idx]
	if peek.plays_on_board():
		_resolve_free_skill_play(idx)
		return true
	if not peek.can_drop_on(unit):
		return false
	var card := _deck.play_hand_index(idx)
	if card == null:
		return false
	_apply_unit_targeted_card(card, unit)
	return true


## GUI 验收：模拟拖非通用技到目标格（高亮+箭头）；返回 false 若卡/施法者缺失。
func capture_skill_drag_preview(kind_name: String, hover_unit_id: String = "") -> bool:
	var want := TacticalActionCardScript.Kind.SKILL_BURN_ATTACK
	match kind_name:
		"skill_draw":
			want = TacticalActionCardScript.Kind.SKILL_DRAW
		"skill_inspire":
			want = TacticalActionCardScript.Kind.SKILL_INSPIRE
		"skill_burn_attack":
			want = TacticalActionCardScript.Kind.SKILL_BURN_ATTACK
		"skill_stealth":
			want = TacticalActionCardScript.Kind.SKILL_STEALTH
		"skill_volley":
			want = TacticalActionCardScript.Kind.SKILL_VOLLEY
		_:
			want = TacticalActionCardScript.Kind.SKILL_BURN_ATTACK
	var peek: TacticalActionCard = null
	for c in _deck.hand:
		if c.kind == want:
			peek = c
			break
	if peek == null or not peek.plays_on_board():
		return false
	var caster := peek.find_bound_caster(_board)
	if caster == null:
		return false
	var release_cells: Array[Vector2i] = peek.release_preview_cells(_board)
	if release_cells.is_empty():
		return false
	var hover_cell: Vector2i = release_cells[0]
	if hover_unit_id != "":
		for u in _board.living_units():
			if u.def != null and u.def.id == hover_unit_id and u.cell in release_cells:
				hover_cell = u.cell
				break
	elif release_cells.size() > 1:
		# 优先选非施法者格，箭头更可读。
		for c in release_cells:
			if c != caster.cell:
				hover_cell = c
				break
	_board_view.set_card_drag_hover(hover_cell, _board.unit_at(hover_cell), true)
	_board_view.set_skill_drag_preview(caster.cell, hover_cell, release_cells, true)
	_last_log = "拖技预览：%s → %s" % [peek.display_label(), hover_cell]
	_refresh_hand_ui()
	return true


## 鼓手/游侠等：打出攻击牌时的触发被动日志拼到 _last_log。
func _append_attack_card_passive_logs() -> void:
	var logs := TacticalAbilitySystemScript.process_player_attack_card_played(_board)
	if logs.is_empty():
		return
	if _last_log.is_empty():
		_last_log = "；".join(logs)
	else:
		_last_log = "%s · %s" % [_last_log, "；".join(logs)]
