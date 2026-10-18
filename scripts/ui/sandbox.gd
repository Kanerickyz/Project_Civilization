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

var _clock: TurnClock
var _turn_label: Label
var _hint_label: Label
var _unit_panel: Label
var _end_turn_button: Button
var _board_config: BoardConfig
var _board_view: GridBoardView
var _board: TacticalBoard
var _selected_unit: TacticalUnitInstance
var _last_log: String = ""
var _input_locked: bool = false
var _game_over: bool = false
var _turn_banner: Label
var _game_over_panel: PanelContainer
var _game_over_title: Label


func _ready() -> void:
	UiThemeScript.apply(self)
	_clock = TurnClockScript.new()
	_board_config = _load_board_config()
	_board = TacticalSandboxRosterScript.build_demo_board(
		_board_config.grid_width, _board_config.grid_height
	)
	_board.changed.connect(_on_board_changed)
	_build()
	_fire_battle_start_triggers()
	_apply_side_turn_start_triggers(TacticalFactionScript.Id.PLAYER)
	_refresh_all()
	_show_turn_banner()


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
	_board_view.cell_clicked.connect(_on_cell_clicked)

	var top_bar := MarginContainer.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_bar.add_theme_constant_override("margin_left", 10)
	top_bar.add_theme_constant_override("margin_top", 6)
	top_bar.add_theme_constant_override("margin_right", 10)
	top_bar.add_theme_constant_override("margin_bottom", 0)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(top_row)

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
	top_row.add_child(_hint_label)

	var side_panel := PanelContainer.new()
	side_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	side_panel.offset_left = -168.0
	side_panel.offset_top = -120.0
	side_panel.offset_right = -8.0
	side_panel.offset_bottom = 120.0
	side_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(side_panel)

	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 6)
	side_panel.add_child(side_box)

	_unit_panel = Label.new()
	_unit_panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_panel.custom_minimum_size = Vector2(150, 0)
	_unit_panel.add_theme_font_size_override("font_size", 13)
	side_box.add_child(_unit_panel)

	var bottom_bar := MarginContainer.new()
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_bar.add_theme_constant_override("margin_left", 10)
	bottom_bar.add_theme_constant_override("margin_top", 0)
	bottom_bar.add_theme_constant_override("margin_right", 10)
	bottom_bar.add_theme_constant_override("margin_bottom", 8)
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_bar)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_BEGIN
	bottom_bar.add_child(actions)

	_end_turn_button = Button.new()
	_end_turn_button.text = "结束行动"
	_end_turn_button.custom_minimum_size = Vector2(96, 32)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	actions.add_child(_end_turn_button)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 32)
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)

	_turn_banner = Label.new()
	_turn_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_turn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_banner.add_theme_font_size_override("font_size", 28)
	_turn_banner.add_theme_color_override("font_color", Color("f0f4ff"))
	_turn_banner.modulate.a = 0.0
	_turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_turn_banner)

	_game_over_panel = PanelContainer.new()
	_game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_over_panel.offset_left = -140.0
	_game_over_panel.offset_top = -72.0
	_game_over_panel.offset_right = 140.0
	_game_over_panel.offset_bottom = 72.0
	_game_over_panel.visible = false
	_game_over_panel.mouse_filter = Control.MOUSE_FILTER_STOP
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


func _on_board_changed() -> void:
	if not _input_locked:
		_refresh_all()


func _refresh_all() -> void:
	_turn_label.text = "对战 · %s" % _clock.status_text()
	var mode := ""
	if _selected_unit != null:
		mode = " · 已选 %s" % _selected_unit.def.display_name
	_hint_label.text = "%dx%d 方格%s · %s" % [
		_board_config.grid_width,
		_board_config.grid_height,
		mode,
		_last_log if _last_log != "" else "点选己方单位 · 绿=可移动 · 红=攻击距离",
	]
	_refresh_unit_panel()
	_refresh_action_buttons()
	var move_cells: Array = []
	var attack_cells: Array = []
	var sel_cell := Vector2i(-1, -1)
	if _selected_unit != null and _clock.player_active and not _game_over:
		sel_cell = _selected_unit.cell
		if _selected_unit.faction == TacticalFactionScript.Id.PLAYER:
			move_cells = _board.reachable_move_cells(_selected_unit)
			attack_cells = _board.attack_range_cells(_selected_unit)
	elif _selected_unit != null:
		sel_cell = _selected_unit.cell
	_board_view.sync_tactical_units(
		_board.living_units(), sel_cell, move_cells, attack_cells
	)


func _refresh_action_buttons() -> void:
	var player_turn := _clock.player_active and not _game_over
	_end_turn_button.disabled = not player_turn or _input_locked


func _refresh_unit_panel() -> void:
	if _selected_unit == null or not _selected_unit.is_alive():
		_unit_panel.text = "未选中单位\n（玩家回合可点蓝方）"
		return
	var u := _selected_unit
	var ab := u.def.triggered_ability
	var skill_line := ab.display_name if ab != null else "—"
	var skill_rules := ab.rules_hint if ab != null else ""
	_unit_panel.text = (
		"%s · %s\nHP %d/%d · 攻 %d · 移 %d · 射程 %d\n%s\n%s"
		% [
			u.def.display_name,
			TacticalFactionScript.label(u.faction),
			u.hp,
			u.def.max_hp,
			u.effective_attack(),
			u.def.move_range,
			u.def.attack_range,
			skill_line,
			skill_rules,
		]
	)


func _show_turn_banner() -> void:
	if _game_over:
		return
	_turn_banner.text = _clock.status_text()
	_turn_banner.modulate.a = 1.0
	_turn_banner.scale = Vector2(0.92, 0.92)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_turn_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(_turn_banner, "modulate:a", 0.0, 0.55).set_delay(0.65)


func _on_cell_clicked(cell: Vector2i) -> void:
	if _input_locked or _game_over or not _clock.player_active:
		return

	var clicked := _board.unit_at(cell)
	if clicked != null:
		if clicked.faction == TacticalFactionScript.Id.PLAYER:
			_selected_unit = clicked
			_refresh_all()
		elif (
			_selected_unit != null
			and _selected_unit.faction == TacticalFactionScript.Id.PLAYER
		):
			var atk := TacticalCombatScript.try_basic_attack(
				_board, _selected_unit, cell, TacticalFactionScript.Id.PLAYER
			)
			_last_log = atk["log"]
			if atk["ok"]:
				_feedback_from_attack(clicked, atk)
				_check_victory()
		_refresh_all()
		return

	if _selected_unit != null and _selected_unit.faction == TacticalFactionScript.Id.PLAYER:
		if _board.try_move(_selected_unit, cell):
			_last_log = "%s 移动至 (%d,%d)" % [
				_selected_unit.def.display_name, cell.x, cell.y
			]
	_refresh_all()


func _feedback_from_attack(target: TacticalUnitInstance, res: Dictionary) -> void:
	var dmg: int = int(res.get("damage", 0))
	_board_view.play_damage_popup(target.cell, dmg)
	_board_view.play_unit_hit(target)
	if res.get("killed", false):
		_board_view.play_unit_death(target)
		if _selected_unit == target:
			_selected_unit = null


func _on_end_turn_pressed() -> void:
	if _input_locked or _game_over or not _clock.player_active:
		return
	_clock.end_turn()
	_board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	_apply_side_turn_start_triggers(TacticalFactionScript.Id.OPPONENT)
	_selected_unit = null
	_show_turn_banner()
	_refresh_all()
	_run_opponent_turn_async()


func _run_opponent_turn_async() -> void:
	_input_locked = true
	_refresh_action_buttons()
	await get_tree().process_frame
	var events := TacticalEnemyAiScript.run_opponent_turn(_board)
	for ev in events:
		var kind: String = ev.get("kind", "")
		if kind == "attack":
			var res: Dictionary = ev["result"]
			var cell: Vector2i = ev["cell"]
			var target := _board.unit_at(cell)
			if target != null:
				_board_view.play_damage_popup(cell, int(res.get("damage", 0)))
				_board_view.play_unit_hit(target)
				if res.get("killed", false):
					await get_tree().create_timer(0.25).timeout
					_board_view.play_unit_death(target)
		elif kind == "move":
			_last_log = "对手 %s 移动" % (ev["unit"] as TacticalUnitInstance).def.display_name
		_refresh_all()
		await get_tree().create_timer(0.32).timeout
		if _check_victory():
			return

	_clock.end_turn()
	_board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	_apply_side_turn_start_triggers(TacticalFactionScript.Id.PLAYER)
	_last_log = "对手结束行动"
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
			_refresh_all()
			return
