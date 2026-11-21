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
const TacticalActionPreviewScript := preload("res://scripts/units/tactical_action_preview.gd")
const ActionHandFanScript := preload("res://scripts/ui/action_hand_fan.gd")
const TacticalUnitInfoCardScript := preload("res://scripts/ui/tactical_unit_info_card.gd")
const KillImpactFxScript := preload("res://scripts/ui/kill_impact_fx.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")

enum PendingKind { NONE, MOVE, ATTACK, STEALTH, CHARGE, HEAL_POTION }

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
## 拖攻击/加强攻时记住悬停过的己方攻击者，便于继续拖到敌方预览整条链路（A）。
var _drag_attack_caster: TacticalUnitInstance = null
var _hand_fan: ActionHandFan
var _last_log: String = ""
var _input_locked: bool = false
## 玩家结束行动（含空手自动结束）进行中，防止重入把回合钟多拨一次而跳过对手段。
var _ending_player_action: bool = false
## 技能提示 / 反应攻击串行播放中（含 kick 的 _play_passive_fx）。
var _skill_fx_playing: bool = false
## 回合开始 STS 逐张抽牌动画中：跳过 _refresh_hand_ui，避免整手闪现。
var _hand_draw_animating: bool = false
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
	_last_log = "战斗开始 · 抽牌中"
	await _begin_player_turn_with_draw_async()
	_last_log = "战斗开始 · 已抽手牌"
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
		# 先冻结死亡位并播淡出/剪影，再 refresh（sync 会保留 dying 节点）。
		for dead in killed_now:
			_board_view.play_unit_death(dead)
			if _selected_unit == dead:
				_selected_unit = null
			if _focus_unit == dead:
				_focus_unit = null
				_pending_kind = PendingKind.NONE
		_play_kill_impacts(killed_now)
		_refresh_all()
		# 给飘字 + 死亡淡出一拍可见窗口，再让本方单位执行意图/出牌。
		await get_tree().create_timer(0.38).timeout
		await _await_presentation_idle_async()
		if killed_now.size() > 0:
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
	_board_view.cell_hovered.connect(_on_cell_hovered)
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
	if _board_view != null:
		_board_view.clear_skill_drag_preview()
		_board_view.clear_action_preview()
	# 取消瞄准：已打牌不回手，清空该单位全部攻击授权（含连拖叠加）。
	if _focus_unit != null and _deck.is_attack_authorized(_focus_unit):
		_deck.clear_attack_authorization(_focus_unit)
	else:
		_deck.pending_attack_bonus = 0
		_deck.pending_aoe_burn_stacks = 0
		_deck.pending_volley = false
	if not keep_move_focus:
		_focus_unit = null
	elif (
		_focus_unit != null
		and _focus_unit.is_alive()
		and _deck.is_move_authorized(_focus_unit)
	):
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
		elif _pending_kind == PendingKind.CHARGE:
			attack_cells = TacticalCombatScript.charge_preview_cells(_board, _focus_unit.cell)
		elif _pending_kind == PendingKind.HEAL_POTION:
			# 金 overlay 在 sync 后由 set_skill_drag_preview 叠加。
			pass
	elif _selected_unit != null and _selected_unit.is_alive():
		sel_cell = _selected_unit.cell
		# 敌方状态机单位：点选即展示可行动邻域 + 下一回合意图虚影。
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
	# 恢复药水瞄准：金规则格 = 医师周围 ≤ attack_range。
	if (
		_pending_kind == PendingKind.HEAL_POTION
		and _focus_unit != null
		and _focus_unit.is_alive()
		and not _in_deployment
		and _board_view != null
	):
		var gold_cells: Array[Vector2i] = _heal_potion_aim_cells(_focus_unit)
		_board_view.set_skill_drag_preview(_focus_unit.cell, null, gold_cells, false)


func _compose_hint() -> String:
	if _in_deployment:
		if _last_log != "":
			return _last_log
		return "部署：拖己方到左半盘 · 「开始战斗」"
	if _pending_kind == PendingKind.MOVE and _focus_unit != null:
		return "移动中：%s · 点绿格（本卡一次 · 步数 ≤%d）" % [
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
	if _pending_kind == PendingKind.CHARGE and _focus_unit != null:
		return "冲撞：%s · 点红圈方向格（最多 3 格）" % _focus_unit.def.display_name
	if _pending_kind == PendingKind.HEAL_POTION and _focus_unit != null:
		return "恢复药水：%s · 点金圈落点（该格一格内友方各+2血）" % _focus_unit.def.display_name
	if _last_log != "":
		return _last_log
	return "点己方移动 / 拖移攻卡 · 技能卡短按/拖棋盘 · 库 %d · 弃 %d" % [
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
		_unit_panel.text = "未选中单位\n（拖移动/攻击卡行动）"
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
	if _hand_draw_animating:
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


## 玩家行动段开始：先锁输入再抽牌数据，UI 逐张飞入（STS）；期间刷新跳过手牌整手闪现。
func _begin_player_turn_with_draw_async() -> void:
	_hand_draw_animating = true
	_input_locked = true
	_refresh_action_buttons()
	if _hand_fan != null:
		_hand_fan.set_interactive(false)
		_hand_fan.clear_hand()
	_deck.begin_player_turn()
	_refresh_all()
	if _hand_fan != null and _deck != null and not _deck.hand.is_empty():
		var labels: Array[String] = []
		var kinds: Array[int] = []
		var details: Array[String] = []
		for card in _deck.hand:
			labels.append(card.display_label())
			kinds.append(int(card.kind))
			details.append(card.rules_detail())
		await _hand_fan.play_draw_sequence(labels, kinds, details)
	_hand_draw_animating = false
	_input_locked = false
	_refresh_all()


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


## 拖牌跟手：高亮当前格；悬停目标立刻视觉预览整条结算链（A：攻击卡同）。
func _on_hand_card_drag_moved(index: int, global_pos: Vector2) -> void:
	if _board_view == null:
		return
	if _in_deployment or _input_locked or _game_over or not _clock.player_active:
		_drag_attack_caster = null
		_board_view.clear_card_drag_hover()
		return
	if index < 0 or index >= _deck.hand.size():
		_drag_attack_caster = null
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
		_drag_attack_caster = null
		var release_cells: Array[Vector2i] = peek.release_preview_cells(_board)
		var in_release := cell in release_cells
		# 非通用技：仅规则格（金 overlay）可松手；格外悬停标无效。
		valid = in_release
		if unit != null and unit.is_alive():
			hover_unit = unit
		var caster := peek.find_bound_caster(_board)
		_board_view.set_card_drag_hover(cell, hover_unit, valid)
		if caster != null:
			_board_view.set_skill_drag_preview(caster.cell, cell, release_cells, in_release)
		else:
			_board_view.set_skill_drag_preview(null, null, release_cells, false)
		if in_release:
			_apply_drag_preview(_preview_for_skill_drag(peek, caster, cell))
		else:
			_board_view.clear_action_preview()
		return
	# 通用攻/加强攻：拖到己方记攻击者并亮攻距；继续拖到可打目标则立刻预览链路。
	if (
		peek != null
		and (
			peek.kind == TacticalActionCardScript.Kind.ATTACK
			or peek.kind == TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK
		)
	):
		_board_view.clear_skill_drag_preview()
		_handle_attack_card_drag_preview(peek, cell, unit)
		return
	_drag_attack_caster = null
	if unit != null and unit.is_alive():
		hover_unit = unit
		valid = (
			unit.faction == TacticalFactionScript.Id.PLAYER
			and peek != null
			and peek.can_drop_on(unit)
		)
	_board_view.clear_skill_drag_preview()
	_board_view.set_card_drag_hover(cell, hover_unit, valid)
	if valid and peek != null:
		_apply_drag_preview(_preview_for_unit_targeted_card(peek, unit))
	else:
		_board_view.clear_action_preview()


## 已授权后的瞄准悬停：仍用同一套视觉预览（拖牌为主路径 A）。
func _on_cell_hovered(cell: Variant) -> void:
	if _board_view == null:
		return
	if (
		_in_deployment
		or _input_locked
		or _game_over
		or not _clock.player_active
		or _pending_kind == PendingKind.NONE
		or _focus_unit == null
	):
		return
	# 拖牌中由 _on_hand_card_drag_moved 负责预览。
	if _hand_fan != null and _hand_fan.is_busy():
		return
	if cell == null or not (cell is Vector2i):
		_board_view.clear_action_preview()
		return
	var c: Vector2i = cell as Vector2i
	var preview := _preview_for_pending_aim(c)
	if bool(preview.get("ok", false)):
		_apply_drag_preview(preview)
	else:
		_board_view.clear_action_preview()


func _apply_drag_preview(preview: Dictionary) -> void:
	if _board_view == null:
		return
	if not bool(preview.get("ok", false)):
		_board_view.clear_action_preview()
		return
	# 攻距 / 可达由 preview 标记驱动；先清再按需叠。
	_board_view.set_preview_move_cells([])
	_board_view.set_preview_attack_cells([])
	if bool(preview.get("show_reachable", false)):
		var mu: TacticalUnitInstance = preview.get("move_unit") as TacticalUnitInstance
		if mu != null:
			_board_view.set_preview_move_cells(_board.preview_reachable_move_cells(mu))
	if bool(preview.get("show_attack_range", false)):
		var au: TacticalUnitInstance = preview.get("attack_unit") as TacticalUnitInstance
		if au != null:
			_board_view.set_preview_attack_cells(_board.attack_range_cells(au))
	_board_view.set_action_preview(preview)


func _handle_attack_card_drag_preview(
	card: TacticalActionCard, cell: Vector2i, unit: TacticalUnitInstance
) -> void:
	var drop_valid := (
		unit != null
		and unit.is_alive()
		and unit.faction == TacticalFactionScript.Id.PLAYER
		and card.can_drop_on(unit)
	)
	if drop_valid:
		_drag_attack_caster = unit
		_board_view.set_card_drag_hover(cell, unit, true)
		_apply_drag_preview(TacticalActionPreviewScript.preview_attack_authorize(unit))
		return
	var caster := _drag_attack_caster
	if caster == null or not caster.is_alive():
		caster = _find_drag_attack_caster_for_target(unit)
		_drag_attack_caster = caster
	if (
		caster != null
		and unit != null
		and unit.is_alive()
		and unit != caster
	):
		var dist := GridMathScript.chebyshev(caster.cell, unit.cell)
		if (
			caster.def.is_chebyshev_in_attack_band(dist)
			and _board.has_attack_los(caster.cell, unit.cell)
		):
			_board_view.set_card_drag_hover(cell, unit, false)
			_apply_drag_preview(
				TacticalActionPreviewScript.preview_basic_attack(
					_board,
					caster,
					unit.cell,
					card.attack_bonus_damage,
					0,
					false,
					true
				)
			)
			# 保留攻距红格，便于看出链路来自哪名攻击者。
			_board_view.set_preview_attack_cells(_board.attack_range_cells(caster))
			return
	_board_view.set_card_drag_hover(cell, unit if unit != null and unit.is_alive() else null, false)
	if caster != null and caster.is_alive():
		_apply_drag_preview(TacticalActionPreviewScript.preview_attack_authorize(caster))
	else:
		_board_view.clear_action_preview()


func _find_drag_attack_caster_for_target(target: TacticalUnitInstance) -> TacticalUnitInstance:
	if target == null or not target.is_alive():
		return null
	var best: TacticalUnitInstance = null
	var best_dist := 999999
	for u in _board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER or u == target:
			continue
		var dist := GridMathScript.chebyshev(u.cell, target.cell)
		if not u.def.is_chebyshev_in_attack_band(dist):
			continue
		if not _board.has_attack_los(u.cell, target.cell):
			continue
		if dist < best_dist:
			best_dist = dist
			best = u
	return best


func _preview_for_unit_targeted_card(
	card: TacticalActionCard, unit: TacticalUnitInstance
) -> Dictionary:
	if card == null or unit == null:
		return {}
	if card.kind == TacticalActionCardScript.Kind.MOVE:
		return TacticalActionPreviewScript.preview_move_authorize(unit)
	match card.kind:
		TacticalActionCardScript.Kind.SKILL_ARMOR:
			return TacticalActionPreviewScript.preview_armor(unit, card.armor_grant)
		_:
			return {}


func _preview_for_skill_drag(
	card: TacticalActionCard, caster: TacticalUnitInstance, cell: Vector2i
) -> Dictionary:
	if card == null:
		return {}
	match card.kind:
		TacticalActionCardScript.Kind.SKILL_HEAL_POTION:
			if caster == null:
				return {}
			return TacticalActionPreviewScript.preview_heal_potion(_board, caster, cell)
		TacticalActionCardScript.Kind.SKILL_INSPIRE:
			if caster == null:
				return {}
			return TacticalActionPreviewScript.preview_inspire(_board, caster)
		TacticalActionCardScript.Kind.SKILL_DRAW:
			return TacticalActionPreviewScript.preview_skill_draw(caster)
		TacticalActionCardScript.Kind.SKILL_STEALTH:
			var t := _board.unit_at(cell)
			if t == null:
				return {}
			return TacticalActionPreviewScript.preview_stealth(t)
		TacticalActionCardScript.Kind.SKILL_CHARGE:
			if caster == null:
				return {}
			return TacticalActionPreviewScript.preview_charge(_board, caster, cell)
		TacticalActionCardScript.Kind.SKILL_VOLLEY, TacticalActionCardScript.Kind.SKILL_BURN_ATTACK:
			if caster == null:
				return {}
			var target := _board.unit_at(cell)
			if target == null or target == caster:
				return TacticalActionPreviewScript.preview_attack_authorize(caster)
			var is_volley := card.kind == TacticalActionCardScript.Kind.SKILL_VOLLEY
			return TacticalActionPreviewScript.preview_basic_attack(
				_board,
				caster,
				cell,
				card.attack_bonus_damage,
				card.aoe_burn_stacks,
				is_volley,
				true
			)
		_:
			return {}


func _preview_for_pending_aim(cell: Vector2i) -> Dictionary:
	if _focus_unit == null:
		return {}
	match _pending_kind:
		PendingKind.ATTACK:
			var target := _board.unit_at(cell)
			if target == null or target == _focus_unit:
				return {}
			var dist := GridMathScript.chebyshev(_focus_unit.cell, cell)
			if not _focus_unit.def.is_chebyshev_in_attack_band(dist):
				return {}
			if not _board.has_attack_los(_focus_unit.cell, cell):
				return {}
			return TacticalActionPreviewScript.preview_basic_attack(
				_board,
				_focus_unit,
				cell,
				_deck.pending_attack_bonus,
				_deck.pending_aoe_burn_stacks,
				_deck.pending_volley,
				true
			)
		PendingKind.CHARGE:
			var charge_cells: Array[Vector2i] = TacticalCombatScript.charge_preview_cells(
				_board, _focus_unit.cell
			)
			if not (cell in charge_cells):
				return {}
			return TacticalActionPreviewScript.preview_charge(_board, _focus_unit, cell)
		PendingKind.HEAL_POTION:
			if not (cell in _heal_potion_aim_cells(_focus_unit)):
				return {}
			return TacticalActionPreviewScript.preview_heal_potion(_board, _focus_unit, cell)
		PendingKind.MOVE:
			return TacticalActionPreviewScript.preview_move_step(_board, _focus_unit, cell)
		PendingKind.STEALTH:
			var st := _board.unit_at(cell)
			if st == null:
				return {}
			return TacticalActionPreviewScript.preview_stealth(st)
		_:
			return {}


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


## 单位目标卡拖到己方单位；非通用技须松在规则格。无效回手。
## 瞄准类技若松手落在合法目标格上：打出后立刻结算，无需再点一次。
func _on_hand_card_dropped(index: int, global_pos: Vector2) -> void:
	_drag_attack_caster = null
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
	# 非通用技：须落到规则格（金 overlay）；无效格/手牌区松手回手。短按仍可自由打出。
	if peek != null and peek.plays_on_board():
		if peek.find_bound_caster(_board) == null:
			_last_log = "施法者不在场 · 卡已回手"
			_hand_fan.notify_drop_resolved(false)
			_refresh_all()
			return
		if cell_v == null or not peek.is_valid_release_cell(_board, cell_v as Vector2i):
			_last_log = "落点无效 · 卡已回手"
			_hand_fan.notify_drop_resolved(false)
			_refresh_all()
			return
		_hand_fan.notify_drop_resolved(true)
		_resolve_free_skill_play(index)
		_try_complete_aim_at_drop_cell(cell_v)
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
	# 通用攻击/加强攻拖到己方后仍须点红圈；此处不自动结算。


## 自由打出瞄准技后：若松手格已是合法目标，立刻结算（万箭/燃爆/隐身/冲撞/恢复药水）。
func _try_complete_aim_at_drop_cell(cell_v: Variant) -> void:
	if cell_v == null or _focus_unit == null or _input_locked or _game_over:
		return
	var cell: Vector2i = cell_v
	if _pending_kind == PendingKind.ATTACK:
		if not _deck.is_attack_authorized(_focus_unit):
			return
		var clicked := _board.unit_at(cell)
		if clicked == null or clicked == _focus_unit or not clicked.is_alive():
			return
		var atk_dist := GridMathScript.chebyshev(_focus_unit.cell, clicked.cell)
		if not _focus_unit.def.is_chebyshev_in_attack_band(atk_dist):
			return
		if not _board.has_attack_los(_focus_unit.cell, clicked.cell):
			return
		_run_player_attack_async(clicked.cell, clicked)
		return
	if _pending_kind == PendingKind.STEALTH:
		var stealth_target := _board.unit_at(cell)
		if stealth_target == null or not stealth_target.is_alive():
			return
		var stealth_res: Dictionary = _board.apply_grant_stealth(_focus_unit, stealth_target)
		_pending_kind = PendingKind.NONE
		_last_log = str(stealth_res.get("log", "隐身"))
		_play_passive_fx(stealth_res.get("passive_fx", []) as Array)
		_refresh_all()
		_maybe_auto_end_player_turn_if_hand_empty()
		return
	if _pending_kind == PendingKind.CHARGE:
		var charge_cells: Array[Vector2i] = TacticalCombatScript.charge_preview_cells(
			_board, _focus_unit.cell
		)
		if cell in charge_cells:
			_run_player_charge_async(cell)
		return
	if _pending_kind == PendingKind.HEAL_POTION:
		_resolve_heal_potion_at(cell)


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
		_deck.authorize_move(target)
		_pending_kind = PendingKind.MOVE
		_last_log = "移动：%s · 点绿格（本卡仅一次）" % target.def.display_name
	elif card.kind == TacticalActionCardScript.Kind.SKILL_ARMOR:
		var grant := maxi(1, card.armor_grant)
		target.add_armor(grant)
		_pending_kind = PendingKind.NONE
		_last_log = "护甲：%s +%d（现 %d）· 伤害先打护甲，溢出不穿血" % [
			target.def.display_name,
			grant,
			target.armor,
		]
		if _board_view != null:
			_board_view.play_passive_float_text(
				target.cell, "+%d甲" % grant, Color("9ec8ff")
			)
	elif card.kind == TacticalActionCardScript.Kind.SKILL_INSPIRE:
		var inspire: Dictionary = _board.apply_inspire_frenzy(target, 1)
		_pending_kind = PendingKind.NONE
		_last_log = str(inspire.get("log", "鼓舞"))
		_play_passive_fx(inspire.get("passive_fx", []) as Array)
	elif card.kind == TacticalActionCardScript.Kind.SKILL_STEALTH:
		_pending_kind = PendingKind.STEALTH
		_last_log = "隐身：%s · 点任意存活单位" % target.def.display_name
	elif card.kind == TacticalActionCardScript.Kind.SKILL_CHARGE:
		_pending_kind = PendingKind.CHARGE
		_last_log = "冲撞：%s · 点红圈方向格（最多 3 格；路径单位受伤并撞开）" % target.def.display_name
	elif card.kind == TacticalActionCardScript.Kind.SKILL_HEAL_POTION:
		_pending_kind = PendingKind.HEAL_POTION
		_last_log = "恢复药水：%s · 点金圈落点（该格一格内友方各+2血）" % target.def.display_name
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
		# 鼓手等 ON_PLAYER_ATTACK_CARD：须等选定有效目标并成功结算后再触发（授权/取消/无效不触发）。
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

	# 移动瞄准：须已打出移动卡授权；点绿格走一步后本卡用完。
	if _pending_kind == PendingKind.MOVE and _focus_unit != null:
		if not _deck.is_move_authorized(_focus_unit):
			_last_log = "无移动授权 · 请拖移动卡到己方"
			_pending_kind = PendingKind.NONE
			_refresh_all()
			return
		if clicked != null:
			_last_log = "移动请点空绿格"
			_refresh_all()
			return
		if not _board.is_passable(cell):
			_last_log = "%s不可通行" % _board.terrain_display_name(cell)
			_refresh_all()
			return
		if _focus_unit.remaining_move_budget <= 0:
			_last_log = "%s 无移力 · 请再拖移动卡" % _focus_unit.def.display_name
			_pending_kind = PendingKind.NONE
			_refresh_all()
			return
		if _board.try_move(_focus_unit, cell):
			_deck.consume_move_authorization(_focus_unit)
			_pending_kind = PendingKind.NONE
			_last_log = "%s 移动至 (%d,%d) · 本卡已用完" % [
				_focus_unit.def.display_name,
				cell.x,
				cell.y,
			]
			_refresh_all()
			_input_locked = true
			_refresh_action_buttons()
			await get_tree().create_timer(_board_view.unit_move_duration_sec()).timeout
			_input_locked = false
			_refresh_all()
			_maybe_auto_end_player_turn_if_hand_empty()
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
		_play_passive_fx(stealth_res.get("passive_fx", []) as Array)
		_refresh_all()
		_maybe_auto_end_player_turn_if_hand_empty()
		return

	# 盾卫冲撞瞄准：点方向格（红圈内）。
	if _pending_kind == PendingKind.CHARGE and _focus_unit != null:
		var charge_cells: Array[Vector2i] = TacticalCombatScript.charge_preview_cells(
			_board, _focus_unit.cell
		)
		if cell in charge_cells:
			_run_player_charge_async(cell)
			return
		_last_log = "请点红圈方向格，或取消目标"
		_refresh_all()
		return

	# 医师恢复药水：点金规则格落点。
	if _pending_kind == PendingKind.HEAL_POTION and _focus_unit != null:
		if _resolve_heal_potion_at(cell):
			return
		_last_log = "请点金圈落点格，或取消目标"
		_refresh_all()
		return

	# 无待结算卡：点单位仅查看；移动须拖移动卡。
	if clicked != null:
		_selected_unit = clicked
		_focus_unit = null
		_pending_kind = PendingKind.NONE
		if clicked.faction == TacticalFactionScript.Id.PLAYER:
			_last_log = "已选 %s · 拖移动/攻击卡行动" % clicked.def.display_name
		elif TacticalEnemyAiScript.uses_behavior_sm(clicked):
			_last_log = "查看 %s · 绿=可移动 · 红=可攻击 · 虚影=下回合意图" % clicked.def.display_name
		else:
			_last_log = "查看 %s" % clicked.def.display_name
		_refresh_all()
		return
	if not _board.is_passable(cell):
		_last_log = "%s不可通行" % _board.terrain_display_name(cell)
	_refresh_all()


func _run_player_charge_async(target_cell: Vector2i) -> void:
	if _input_locked or _focus_unit == null:
		return
	var knight := _focus_unit
	_input_locked = true
	_refresh_action_buttons()
	var res := TacticalCombatScript.try_knight_charge(_board, knight, target_cell)
	_last_log = str(res.get("log", "冲撞"))
	if not res.get("ok", false):
		_input_locked = false
		_refresh_all()
		return
	_pending_kind = PendingKind.NONE
	# 逻辑已落到终格；一次 refresh 播冲撞位移 Tween，再反馈路径命中。
	_refresh_all()
	var path: Array = res.get("path", []) as Array
	if not path.is_empty():
		await get_tree().create_timer(_board_view.unit_move_duration_sec()).timeout
	var hits: Array = res.get("hits", []) as Array
	var charge_killed: Array = []
	for hit in hits:
		if hit is Dictionary:
			await _feedback_from_charge_hit(hit as Dictionary, charge_killed)
	if int(res.get("self_damage", 0)) > 0 and knight != null:
		_board_view.play_damage_popup(knight.cell, int(res["self_damage"]))
		_board_view.play_unit_hit(knight)
		if bool(res.get("self_killed", false)):
			_purge_dead_unit_cards(knight)
			_board_view.play_unit_death(knight)
			charge_killed.append(knight)
			if _selected_unit == knight:
				_selected_unit = null
			if _focus_unit == knight:
				_focus_unit = null
	_play_kill_impacts(charge_killed)
	await _play_skill_fx_async(res.get("passive_fx", []) as Array)
	_pending_kind = PendingKind.NONE
	_check_victory()
	await _await_presentation_idle_async()
	_input_locked = false
	_refresh_all()
	_maybe_auto_end_player_turn_if_hand_empty()


func _feedback_from_charge_hit(hit: Dictionary, killed_out: Array = []) -> void:
	var vu: TacticalUnitInstance = hit.get("unit") as TacticalUnitInstance
	var vcell: Vector2i = hit.get("cell", Vector2i(-1, -1)) as Vector2i
	var vdmg: int = int(hit.get("damage", 0))
	if vu == null or vdmg <= 0:
		return
	_board_view.play_damage_popup(vcell if vcell.x >= 0 else vu.cell, vdmg)
	_board_view.play_unit_hit(vu)
	if bool(hit.get("killed", false)):
		_purge_dead_unit_cards(vu)
		_board_view.play_unit_death(vu)
		killed_out.append(vu)
		if _selected_unit == vu:
			_selected_unit = null
		if _focus_unit == vu:
			_focus_unit = null
	elif bool(hit.get("knock_moved", false)) and vu.is_alive():
		_refresh_all()
		await get_tree().create_timer(_board_view.unit_move_duration_sec()).timeout


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
	# 逻辑可能已击退/击杀：表现 hold 旧格，等冲刺+受击后再 release。
	if bool(atk.get("killed", false)):
		_board_view.hold_dead_unit_visual(target)
	elif bool(atk.get("knockback_moved", false)):
		var kb_from: Vector2i = atk.get("knockback_from", Vector2i(-1, -1)) as Vector2i
		if kb_from.x >= 0:
			_board_view.hold_unit_visual_at_cell(target, kb_from)
	# 先播攻击冲刺/命中/击退/猎召等，再结算「当攻击牌打出时」加成（鼓手等）。
	var tw := _board_view.play_unit_attack(attacker, target_cell)
	if tw != null:
		await tw.finished
	await _feedback_from_attack(target, atk, target_cell)
	await _append_attack_card_passive_logs()
	_pending_kind = PendingKind.NONE
	# 同单位连拖多张攻击卡：仍有余次则继续瞄准。
	if attacker.is_alive() and _deck.is_attack_authorized(attacker):
		_pending_kind = PendingKind.ATTACK
		_focus_unit = attacker
	_check_victory()
	# 等死亡淡出/剪影/飘字播完再 unlock+refresh，避免尸体被 sync 提前拆掉。
	await _await_presentation_idle_async()
	_input_locked = false
	_refresh_all()
	# 攻击/友方死亡抽牌等补牌结算完后再判空手。
	_maybe_auto_end_player_turn_if_hand_empty()


## 连锁/溅射等多段命中、被动飘字之间的播放间隔（与同格飘字 0.4s 对齐）。
const SKILL_PLAY_INTERVAL_SEC := 0.4


func _feedback_from_attack(
	target: TacticalUnitInstance, res: Dictionary, hit_cell: Vector2i = Vector2i(-1, -1)
) -> void:
	# 表现序：受击（仍 hold 在命中格）→ 死亡淡出 → 再 release 击退。禁止先改格可视化。
	var dmg: int = int(res.get("damage", 0))
	var popup_cell := hit_cell
	if popup_cell.x < 0:
		var from_kb: Vector2i = res.get("knockback_from", Vector2i(-1, -1)) as Vector2i
		popup_cell = from_kb if from_kb.x >= 0 else target.cell
	_board_view.play_damage_popup(popup_cell, dmg)
	var hit_tw: Tween = _board_view.play_unit_hit(target)
	var killed_now: Array = []
	if res.get("killed", false):
		_purge_dead_unit_cards(target)
		_board_view.play_unit_death(target)
		killed_now.append(target)
		if _selected_unit == target:
			_selected_unit = null
		if _focus_unit == target:
			_focus_unit = null
			_pending_kind = PendingKind.NONE
	# 主目标受击播完再播碰撞/齐发/击退，避免 hold 被 snap 到落点。
	if hit_tw != null and is_instance_valid(hit_tw):
		await hit_tw.finished
	var col: TacticalUnitInstance = res.get("collision_target") as TacticalUnitInstance
	var col_dmg: int = int(res.get("collision_damage", 0))
	if col != null and col_dmg > 0:
		await get_tree().create_timer(SKILL_PLAY_INTERVAL_SEC).timeout
		_board_view.play_damage_popup(col.cell, col_dmg)
		var col_hit: Tween = _board_view.play_unit_hit(col)
		if res.get("collision_killed", false):
			_purge_dead_unit_cards(col)
			_board_view.play_unit_death(col)
			killed_now.append(col)
			if _selected_unit == col:
				_selected_unit = null
			if _focus_unit == col:
				_focus_unit = null
				_pending_kind = PendingKind.NONE
		if col_hit != null and is_instance_valid(col_hit):
			await col_hit.finished
	var volley_hits: Array = res.get("volley_hits", []) as Array
	for hit in volley_hits:
		if not (hit is Dictionary):
			continue
		var vu: TacticalUnitInstance = (hit as Dictionary).get("unit") as TacticalUnitInstance
		var vcell: Vector2i = (hit as Dictionary).get("cell", Vector2i(-1, -1)) as Vector2i
		var vdmg: int = int((hit as Dictionary).get("damage", 0))
		if vu == null or vdmg <= 0:
			continue
		await get_tree().create_timer(SKILL_PLAY_INTERVAL_SEC).timeout
		_board_view.play_damage_popup(vcell if vcell.x >= 0 else vu.cell, vdmg)
		var vhit: Tween = _board_view.play_unit_hit(vu)
		if bool((hit as Dictionary).get("killed", false)):
			_purge_dead_unit_cards(vu)
			_board_view.play_unit_death(vu)
			killed_now.append(vu)
			if _selected_unit == vu:
				_selected_unit = null
			if _focus_unit == vu:
				_focus_unit = null
				_pending_kind = PendingKind.NONE
		if vhit != null and is_instance_valid(vhit):
			await vhit.finished
	# 同次结算多死：伤害可分拍，击杀红带+剪影一次同闪（各锚死亡位）。
	_play_kill_impacts(killed_now)
	# 击退：敌已到格且攻击/受击播完后，再 release + refresh 播位移。
	if res.get("knockback_moved", false) and target != null and target.is_alive():
		var kb_from: Vector2i = res.get("knockback_from", Vector2i(-1, -1)) as Vector2i
		if kb_from.x >= 0:
			_board_view.release_held_unit_visual(target, kb_from)
		_refresh_all()
		await get_tree().process_frame
		await _await_presentation_idle_async()
	# 猎召等反应攻击 / 被动飘字：按队列串行（动画+飘字）。
	await _play_skill_fx_async(res.get("passive_fx", []) as Array)


func _unit_kill_silhouette_tex(unit: TacticalUnitInstance) -> Texture2D:
	if unit == null or unit.def == null:
		return null
	if unit.faction == TacticalFactionScript.Id.OPPONENT:
		return unit.def.texture_red
	return unit.def.texture_blue


func _unit_kill_silhouette_screen_size(unit: TacticalUnitInstance, tex: Texture2D) -> Vector2:
	if tex == null or _board_view == null:
		return Vector2.ZERO
	var vis := 1.0
	if unit != null and unit.def != null and unit.def.visual_scale > 0.0:
		vis = unit.def.visual_scale
	if _board_view.has_method("unit_texture_screen_size"):
		return _board_view.unit_texture_screen_size(tex, vis)
	return Vector2.ZERO


## 死亡单位标记 → KillImpactFx 局部坐标；无单位/棋盘时回退 INF（FX 居中）。
func _unit_kill_silhouette_anchor_local(unit: TacticalUnitInstance) -> Vector2:
	if unit == null or _board_view == null or _kill_impact == null:
		return Vector2.INF
	if not _board_view.has_method("unit_screen_position"):
		return Vector2.INF
	var screen: Vector2 = _board_view.unit_screen_position(unit)
	return _kill_impact.get_global_transform_with_canvas().affine_inverse() * screen


func _play_kill_impact(unit: TacticalUnitInstance = null) -> void:
	var units: Array = []
	if unit != null:
		units.append(unit)
	_play_kill_impacts(units)


## 同批死亡：一条红带冲击 + 每名死者一枚剪影（各锚死亡位）。
func _play_kill_impacts(units: Array) -> void:
	if _game_over or _kill_impact == null:
		return
	var entries: Array = []
	for u_v in units:
		var unit: TacticalUnitInstance = u_v as TacticalUnitInstance
		if unit == null:
			continue
		var tex := _unit_kill_silhouette_tex(unit)
		entries.append(
			{
				"tex": tex,
				"screen_size": _unit_kill_silhouette_screen_size(unit, tex),
				"anchor_local": _unit_kill_silhouette_anchor_local(unit),
			}
		)
	if entries.is_empty():
		return
	if entries.size() == 1 and _kill_impact.has_method("play"):
		var e: Dictionary = entries[0] as Dictionary
		_kill_impact.call(
			"play",
			e.get("tex") as Texture2D,
			e.get("screen_size", Vector2.ZERO) as Vector2,
			e.get("anchor_local", Vector2.INF) as Vector2
		)
		return
	if _kill_impact.has_method("play_many"):
		_kill_impact.call("play_many", entries)


## GUI 截图：强制播一次击杀冲击（默认红狼骑剪影；可传贴图与死亡位锚点单位）。
func capture_play_kill_impact(
	silhouette_tex: Texture2D = null,
	anchor_unit: TacticalUnitInstance = null
) -> bool:
	if _kill_impact == null:
		return false
	var tex := silhouette_tex
	var vis := 1.0
	if tex == null:
		var rider_def: TacticalUnitDef = load("res://resources/units/rider.tres") as TacticalUnitDef
		if rider_def != null:
			tex = rider_def.texture_red
			if rider_def.visual_scale > 0.0:
				vis = rider_def.visual_scale
	var screen_sz := Vector2.ZERO
	if tex != null and _board_view != null and _board_view.has_method("unit_texture_screen_size"):
		screen_sz = _board_view.unit_texture_screen_size(tex, vis)
	var anchor := _unit_kill_silhouette_anchor_local(anchor_unit)
	if _kill_impact.has_method("play"):
		_kill_impact.call("play", tex, screen_sz, anchor)
	return _kill_impact.visible


## GUI 截图：多死者同闪（各锚死亡位）。
func capture_play_kill_impacts(anchor_units: Array) -> bool:
	if _kill_impact == null or anchor_units.is_empty():
		return false
	_play_kill_impacts(anchor_units)
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


## 手牌打完后自动结束行动。须在鸣鼓换手抽牌、盾卫友方死亡抽牌等补牌结算之后调用；
## 攻/隐身/冲撞/恢复药水瞄准未完成时不触发（卡已离手但仍待点目标）。
## 先锁输入再 deferred 启动；进对手段前等技能提示/飘字/反应/击杀剪影等播完。
func _maybe_auto_end_player_turn_if_hand_empty() -> void:
	if not _should_auto_end_player_action():
		return
	_last_log = "手牌已打完 · 自动结束行动"
	_input_locked = true
	_refresh_action_buttons()
	_refresh_all()
	call_deferred("_auto_end_player_action_after_fx_async")


func _auto_end_player_action_after_fx_async() -> void:
	await _await_presentation_idle_async()
	await _end_player_action_async()


func _should_auto_end_player_action() -> bool:
	if _ending_player_action or _in_deployment or _input_locked or _game_over:
		return false
	if _clock == null or not _clock.player_active:
		return false
	if _deck == null or not _deck.hand.is_empty():
		return false
	if (
		_pending_kind == PendingKind.MOVE
		or _pending_kind == PendingKind.ATTACK
		or _pending_kind == PendingKind.STEALTH
		or _pending_kind == PendingKind.CHARGE
		or _pending_kind == PendingKind.HEAL_POTION
	):
		return false
	return true


## 技能串行、飘字队列、被动抖动/位移、击杀红带剪影是否仍在播。
func _is_presentation_busy() -> bool:
	if _skill_fx_playing:
		return true
	if _kill_impact != null and _kill_impact.has_method("is_flashing"):
		if bool(_kill_impact.call("is_flashing")):
			return true
	if _board_view != null and _board_view.has_method("is_combat_presentation_busy"):
		if bool(_board_view.call("is_combat_presentation_busy")):
			return true
	return false


## 等到战斗表现空闲再继续（自动结束进对手段用）；带上限避免死等。
func _await_presentation_idle_async() -> void:
	var guard := 0
	while _is_presentation_busy() and guard < 240:
		await get_tree().create_timer(0.05, true, false, true).timeout
		guard += 1


## 从一批对手事件里收集攻击结算已击杀、但仍需等攻击表现的目标。
func _collect_attack_event_kill_victims(events: Array) -> Array[TacticalUnitInstance]:
	var out: Array[TacticalUnitInstance] = []
	var seen: Dictionary = {}
	for ev in events:
		if str(ev.get("kind", "")) != "attack":
			continue
		var res: Dictionary = ev.get("result", {}) as Dictionary
		_append_attack_kill_victim(out, seen, res.get("target"), bool(res.get("killed", false)))
		_append_attack_kill_victim(
			out, seen, res.get("collision_target"), bool(res.get("collision_killed", false))
		)
		for hit in res.get("volley_hits", []) as Array:
			if not (hit is Dictionary):
				continue
			var hd: Dictionary = hit as Dictionary
			_append_attack_kill_victim(
				out, seen, hd.get("unit"), bool(hd.get("killed", false))
			)
	return out


func _append_attack_kill_victim(
	out: Array[TacticalUnitInstance],
	seen: Dictionary,
	unit_v: Variant,
	killed: bool
) -> void:
	if not killed:
		return
	var unit := unit_v as TacticalUnitInstance
	if unit == null or seen.has(unit):
		return
	seen[unit] = true
	out.append(unit)


## 收集本批攻击事件中已逻辑击退、但仍需等攻击后再播位移的目标。
func _collect_attack_event_knockbacks(events: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for ev in events:
		if str(ev.get("kind", "")) != "attack":
			continue
		var res: Dictionary = ev.get("result", {}) as Dictionary
		if not bool(res.get("knockback_moved", false)):
			continue
		var unit := res.get("target") as TacticalUnitInstance
		var from_cell: Vector2i = res.get("knockback_from", Vector2i(-1, -1)) as Vector2i
		if unit == null or from_cell.x < 0 or seen.has(unit):
			continue
		seen[unit] = true
		out.append({"unit": unit, "from": from_cell, "to": res.get("knockback_to", unit.cell)})
	return out


func _heal_potion_aim_cells(caster: TacticalUnitInstance) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if caster == null or caster.def == null or _board == null:
		return out
	var range_max := caster.def.attack_range
	for gx in range(_board.grid_width):
		for gy in range(_board.grid_height):
			var cell := Vector2i(gx, gy)
			if GridMathScript.chebyshev(caster.cell, cell) <= range_max:
				out.append(cell)
	return out


## 恢复药水瞄准落点结算；合法返回 true。
func _resolve_heal_potion_at(cell: Vector2i) -> bool:
	if _focus_unit == null or not _focus_unit.is_alive():
		return false
	if not (cell in _heal_potion_aim_cells(_focus_unit)):
		return false
	var res: Dictionary = _board.apply_heal_potion(_focus_unit, cell, 2, 1)
	_pending_kind = PendingKind.NONE
	if _board_view != null:
		_board_view.clear_skill_drag_preview()
	_last_log = str(res.get("log", "恢复药水"))
	var fx: Array = res.get("passive_fx", []) as Array
	# 恢复药水路径不锁输入整段；飘字串行由队列承接，此处 kick 异步即可。
	_play_passive_fx(fx)
	_refresh_all()
	_maybe_auto_end_player_turn_if_hand_empty()
	return true


func _on_end_turn_pressed() -> void:
	await _end_player_action_async()


## 玩家结束行动 → 对手段（含 AI）→ 回到玩家。按钮与空手自动结束共用。
func _end_player_action_async() -> void:
	if _ending_player_action or _in_deployment or _game_over:
		return
	if not _clock.player_active:
		return
	_ending_player_action = true
	# 先锁输入，避免弃牌/refresh 重入再次 end_turn 把钟拨回玩家。
	_input_locked = true
	_refresh_action_buttons()
	# 进对手段前再等一拍表现（按钮结束也可能踩在飘字/剪影尾巴上）。
	await _await_presentation_idle_async()
	if _game_over or not _clock.player_active:
		_ending_player_action = false
		_input_locked = false
		_refresh_all()
		return
	_deck.end_player_turn()
	_pending_kind = PendingKind.NONE
	_focus_unit = null
	_selected_unit = null
	_clock.end_turn()
	_board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	_show_turn_banner()
	_refresh_all()
	await _apply_side_turn_start_triggers(TacticalFactionScript.Id.OPPONENT)
	if _game_over:
		_ending_player_action = false
		_input_locked = false
		_refresh_all()
		return
	_refresh_all()
	await _run_opponent_turn_async()
	_ending_player_action = false


func _run_opponent_turn_async() -> void:
	_input_locked = true
	_refresh_action_buttons()
	_refresh_hand_ui()
	await get_tree().process_frame
	var opponents := TacticalEnemyAiScript.sorted_opponents(_board)
	for unit in opponents:
		if not unit.is_alive():
			continue
		# AI 可先数值结算；表现必须 hold→移动→攻击→受击/死/击退，禁止 refresh 抢先反映终态。
		var events := TacticalEnemyAiScript.run_opponent_unit_actions(_board, unit)
		var pending_kills := _collect_attack_event_kill_victims(events)
		var pending_knockbacks := _collect_attack_event_knockbacks(events)
		for victim in pending_kills:
			_board_view.hold_dead_unit_visual(victim)
		for kb in pending_knockbacks:
			_board_view.hold_unit_visual_at_cell(
				kb.get("unit") as TacticalUnitInstance,
				kb.get("from") as Vector2i
			)
		for ev in events:
			var kind: String = ev.get("kind", "")
			if kind == "move":
				var mover := ev["unit"] as TacticalUnitInstance
				_last_log = "对手 %s 移动 · 剩余移力 %d" % [
					mover.def.display_name, mover.remaining_move_budget
				]
				# 移动前再钉一次 hold，防止中途被其它 refresh 冲掉。
				for kb2 in pending_knockbacks:
					_board_view.hold_unit_visual_at_cell(
						kb2.get("unit") as TacticalUnitInstance,
						kb2.get("from") as Vector2i
					)
				for victim2 in pending_kills:
					_board_view.hold_dead_unit_visual(victim2)
				_refresh_all()
				await get_tree().process_frame
				await _await_presentation_idle_async()
			elif kind == "attack":
				var res: Dictionary = ev["result"]
				var cell: Vector2i = ev["cell"]
				var attacker := ev["unit"] as TacticalUnitInstance
				# 攻击前确保目标仍 hold 在命中格。
				for kb3 in pending_knockbacks:
					var ku: TacticalUnitInstance = kb3.get("unit") as TacticalUnitInstance
					if ku != null:
						_board_view.hold_unit_visual_at_cell(ku, kb3.get("from") as Vector2i)
				for victim3 in pending_kills:
					_board_view.hold_dead_unit_visual(victim3)
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
				await _await_presentation_idle_async()
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
			elif kind == "summon":
				var summoner := ev["unit"] as TacticalUnitInstance
				_last_log = str(ev.get("log", "对手召唤"))
				_board_view.play_float_text(
					summoner.cell, "召唤%d" % int(ev.get("amount", 0)), Color("d4a0ff")
				)
				_refresh_all()
				await get_tree().create_timer(0.35).timeout
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
	_last_log = "对手结束行动 · 抽牌中"
	await _begin_player_turn_with_draw_async()
	_last_log = "对手结束行动 · 已抽手牌"
	_show_turn_banner()
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
			_selected_unit = u
			_focus_unit = null
			_pending_kind = PendingKind.NONE
			_last_log = "已选 %s · 拖移动/攻击卡行动" % u.def.display_name
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
## kind_name: move | attack | skill_draw | skill_strong_attack | skill_burn_attack | skill_armor | skill_inspire | skill_stealth | skill_volley | skill_charge | skill_heal_potion
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
		"skill_charge":
			want = TacticalActionCardScript.Kind.SKILL_CHARGE
		"skill_heal_potion":
			want = TacticalActionCardScript.Kind.SKILL_HEAL_POTION
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
		"skill_charge":
			want = TacticalActionCardScript.Kind.SKILL_CHARGE
		"skill_heal_potion":
			want = TacticalActionCardScript.Kind.SKILL_HEAL_POTION
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
	_board_view.set_action_preview(_preview_for_skill_drag(peek, caster, hover_cell))
	_last_log = "拖技预览：%s → %s" % [peek.display_label(), hover_cell]
	_refresh_hand_ui()
	return true


## GUI：拖攻击卡悬停敌方目标，展示视觉伤害链路（PC-107，时机 A）。
func capture_attack_aim_preview(attacker_id: String, target_id: String) -> bool:
	if _board == null or _board_view == null:
		return false
	var attacker: TacticalUnitInstance = null
	var target: TacticalUnitInstance = null
	for u in _board.living_units():
		if u.def == null:
			continue
		if attacker == null and u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == attacker_id:
			attacker = u
		if target == null and u.def.id == target_id and u != attacker:
			target = u
	if attacker == null or target == null:
		return false
	_drag_attack_caster = attacker
	_selected_unit = attacker
	_focus_unit = attacker
	_refresh_all()
	var peek := TacticalActionCardScript.make_attack()
	_handle_attack_card_drag_preview(peek, target.cell, target)
	_last_log = "攻击预览：%s → %s" % [attacker.def.display_name, target.def.display_name]
	return true


## GUI 验收：打出冲撞卡并瞄准到指定方向格（不等动画跑完时可先置位）。
func capture_play_charge_toward(dir_cell: Vector2i) -> bool:
	if not capture_drop_first_card_on_unit("skill_charge", "knight"):
		return false
	if _pending_kind != PendingKind.CHARGE or _focus_unit == null:
		return false
	var cells: Array[Vector2i] = TacticalCombatScript.charge_preview_cells(_board, _focus_unit.cell)
	if not (dir_cell in cells):
		return false
	_run_player_charge_async(dir_cell)
	return true


## 鼓手等：攻击效果播完后结算「当攻击牌打出时」被动；日志拼到 _last_log，并串行播飘字/触发。
func _append_attack_card_passive_logs() -> void:
	var fx: Array = []
	var logs := TacticalAbilitySystemScript.process_player_attack_card_played(_board, fx)
	await _play_skill_fx_async(fx)
	if logs.is_empty():
		return
	if _last_log.is_empty():
		_last_log = "；".join(logs)
	else:
		_last_log = "%s · %s" % [_last_log, "；".join(logs)]


## 兼容截图脚本：kick 串行播放（不等待）。
func _play_passive_fx(fx_list: Array) -> void:
	_play_skill_fx_async(fx_list)


## 被动/猎召等：技能名/抖动播完后，按 sync 批处理效果（同类同步弹、不同类按序）。
func _play_skill_fx_async(fx_list: Array) -> void:
	if _board_view == null or fx_list.is_empty():
		return
	_skill_fx_playing = true
	var started := false
	var i := 0
	while i < fx_list.size():
		var ev: Variant = fx_list[i]
		if not (ev is Dictionary):
			i += 1
			continue
		var d: Dictionary = ev as Dictionary
		var kind := str(d.get("kind", ""))
		if kind == "reaction_attack":
			if started:
				await get_tree().create_timer(SKILL_PLAY_INTERVAL_SEC).timeout
			started = true
			await _play_reaction_attack_async(d)
			i += 1
			continue
		if kind == "skill_prompt":
			if started:
				await get_tree().create_timer(SKILL_PLAY_INTERVAL_SEC).timeout
			started = true
			await _play_skill_prompt_async(d)
			i += 1
			continue
		# 数值/效果：连续同 sync 键一并弹出（如全体 +攻 再全体 +血）。
		var batch: Array = []
		var sync := str(d.get("sync", ""))
		if sync.is_empty():
			batch.append(d)
			i += 1
		else:
			while i < fx_list.size():
				var nxt: Variant = fx_list[i]
				if not (nxt is Dictionary):
					break
				var nd: Dictionary = nxt as Dictionary
				var nkind := str(nd.get("kind", ""))
				if nkind == "reaction_attack" or nkind == "skill_prompt":
					break
				if str(nd.get("sync", "")) != sync:
					break
				batch.append(nd)
				i += 1
		var playable: Array = []
		for b_v in batch:
			var b: Dictionary = b_v as Dictionary
			var cell: Vector2i = b.get("cell", Vector2i(-999, -999)) as Vector2i
			var text := str(b.get("text", ""))
			if text.is_empty() or cell.x <= -900:
				continue
			playable.append(b)
		if playable.is_empty():
			continue
		if started:
			await get_tree().create_timer(SKILL_PLAY_INTERVAL_SEC).timeout
		started = true
		for b_v in playable:
			var b: Dictionary = b_v as Dictionary
			var cell: Vector2i = b.get("cell", Vector2i(-999, -999)) as Vector2i
			var text := str(b.get("text", ""))
			var color: Color = b.get("color", Color("ffe08a")) as Color
			_board_view.play_passive_float_text(cell, text, color)
	_skill_fx_playing = false


## 被动短能力名：飘字 + 单位抖动，等抖动结束再让后续效果入队。
func _play_skill_prompt_async(ev: Dictionary) -> void:
	if _board_view == null:
		return
	var cell: Vector2i = ev.get("cell", Vector2i(-999, -999)) as Vector2i
	var text := str(ev.get("text", ""))
	if text.is_empty() or cell.x <= -900:
		return
	var color: Color = ev.get("color", Color("f5f5f5")) as Color
	_board_view.play_passive_float_text(cell, text, color)
	var unit: TacticalUnitInstance = null
	if _board != null:
		unit = _board.unit_at(cell)
	var tw: Tween = null
	if unit != null and unit.is_alive():
		tw = _board_view.play_passive_trigger(unit)
	if tw != null:
		await tw.finished
	else:
		await get_tree().create_timer(SKILL_PLAY_INTERVAL_SEC).timeout


## 猎召等反应攻击：先播技能名/抖动，再冲刺与命中伤害飘字（不含再入队的 passive_fx）。
func _play_reaction_attack_async(ev: Dictionary) -> void:
	if _board_view == null:
		return
	var attacker: TacticalUnitInstance = ev.get("attacker") as TacticalUnitInstance
	var target: TacticalUnitInstance = ev.get("target") as TacticalUnitInstance
	var target_cell: Vector2i = ev.get("target_cell", Vector2i(-1, -1)) as Vector2i
	var tag := str(ev.get("text", ""))
	var color: Color = ev.get("color", Color("ffe08a")) as Color
	if attacker != null and tag != "":
		var tag_cell: Vector2i = ev.get("cell", attacker.cell) as Vector2i
		_board_view.play_passive_float_text(tag_cell, tag, color)
		var shake_tw: Tween = null
		if attacker.is_alive():
			shake_tw = _board_view.play_passive_trigger(attacker)
		if shake_tw != null:
			await shake_tw.finished
		else:
			await get_tree().create_timer(SKILL_PLAY_INTERVAL_SEC).timeout
	if attacker != null and attacker.is_alive() and target_cell.x >= 0:
		var tw := _board_view.play_unit_attack(attacker, target_cell)
		if tw != null:
			await tw.finished
	if target == null:
		return
	var mini := {
		"damage": int(ev.get("damage", 0)),
		"killed": bool(ev.get("killed", false)),
		"knockback_moved": bool(ev.get("knockback_moved", false)),
		"knockback_from": ev.get("knockback_from", Vector2i(-1, -1)),
		"collision_target": ev.get("collision_target"),
		"collision_damage": int(ev.get("collision_damage", 0)),
		"collision_killed": bool(ev.get("collision_killed", false)),
		"volley_hits": ev.get("volley_hits", []),
		# 嵌套 fx 已按序排在父队列后续事件中，此处不再递归播放。
		"passive_fx": [],
	}
	await _feedback_from_attack(target, mini, target_cell)
