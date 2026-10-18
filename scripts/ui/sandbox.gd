extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main/main_menu.tscn"
const BOARD_CONFIG_PATH := "res://resources/map/board_config.tres"
const TurnClockScript := preload("res://scripts/core/turn_clock.gd")
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")
const GridBoardViewScript := preload("res://scripts/map/grid_board_view.gd")
const BoardConfigScript := preload("res://scripts/map/board_config.gd")
const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

var _clock: TurnClock
var _turn_label: Label
var _hint_label: Label
var _unit_panel: Label
var _skill_button: Button
var _board_config: BoardConfig
var _board_view: GridBoardView
var _board: TacticalBoard
var _selected_unit: TacticalUnitInstance
var _skill_targeting: bool = false
var _last_log: String = ""


func _ready() -> void:
	UiThemeScript.apply(self)
	_clock = TurnClockScript.new()
	_board_config = _load_board_config()
	_board = TacticalSandboxRosterScript.build_demo_board(
		_board_config.grid_width, _board_config.grid_height
	)
	_board.changed.connect(_on_board_changed)
	_build()
	_refresh_all()


func _load_board_config() -> BoardConfig:
	var loaded := load(BOARD_CONFIG_PATH)
	if loaded is BoardConfig:
		return (loaded as BoardConfig).duplicate(true) as BoardConfig
	push_warning("Sandbox: missing %s, using defaults" % BOARD_CONFIG_PATH)
	return BoardConfigScript.new()


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

	_skill_button = Button.new()
	_skill_button.text = "释放技能"
	_skill_button.custom_minimum_size = Vector2(140, 32)
	_skill_button.pressed.connect(_on_skill_pressed)
	side_box.add_child(_skill_button)

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

	var end_turn := Button.new()
	end_turn.text = "结束行动"
	end_turn.custom_minimum_size = Vector2(96, 32)
	end_turn.pressed.connect(_on_end_turn_pressed)
	actions.add_child(end_turn)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 32)
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)


func _on_board_changed() -> void:
	_refresh_all()


func _refresh_all() -> void:
	_turn_label.text = "对战 · %s" % _clock.status_text()
	var mode := ""
	if _skill_targeting:
		mode = " · 选技能目标"
	elif _selected_unit != null:
		mode = " · 已选 %s" % _selected_unit.def.display_name
	_hint_label.text = "%dx%d 方格%s · %s" % [
		_board_config.grid_width,
		_board_config.grid_height,
		mode,
		_last_log if _last_log != "" else "点选己方单位 · 邻格移动 · 技能每段行动一次",
	]
	_refresh_unit_panel()
	_refresh_skill_button()
	var targets: Array = []
	if _skill_targeting and _selected_unit != null and _clock.player_active:
		targets = TacticalAbilitySystemScript.valid_target_cells(
			_board, _selected_unit, TacticalFactionScript.Id.PLAYER
		)
	var sel_cell := Vector2i(-1, -1)
	if _selected_unit != null:
		sel_cell = _selected_unit.cell
	_board_view.sync_tactical_units(_board.living_units(), sel_cell, targets)


func _refresh_unit_panel() -> void:
	if _selected_unit == null:
		_unit_panel.text = "未选中单位\n（玩家回合可点蓝方）"
		return
	var u := _selected_unit
	var ab := u.def.active_ability
	var skill_line := ab.display_name if ab != null else "—"
	var skill_rules := ab.rules_hint if ab != null else ""
	_unit_panel.text = (
		"%s · %s\nHP %d/%d · 攻 %d\n%s\n%s"
		% [
			u.def.display_name,
			TacticalFactionScript.label(u.faction),
			u.hp,
			u.def.max_hp,
			u.effective_attack(),
			skill_line,
			skill_rules,
		]
	)


func _refresh_skill_button() -> void:
	var can := false
	if _clock.player_active and _selected_unit != null:
		can = TacticalAbilitySystemScript.can_cast(
			_selected_unit, TacticalFactionScript.Id.PLAYER
		)
	_skill_button.disabled = not can and not _skill_targeting
	if _skill_targeting:
		_skill_button.text = "取消瞄准"
	else:
		_skill_button.text = "释放技能"


func _on_skill_pressed() -> void:
	if _skill_targeting:
		_skill_targeting = false
		_refresh_all()
		return
	if not _clock.player_active or _selected_unit == null:
		return
	if not TacticalAbilitySystemScript.can_cast(
		_selected_unit, TacticalFactionScript.Id.PLAYER
	):
		return
	_skill_targeting = true
	_refresh_all()


func _on_cell_clicked(cell: Vector2i) -> void:
	if not _clock.player_active:
		return
	if _skill_targeting and _selected_unit != null:
		var res := TacticalAbilitySystemScript.cast(
			_board, _selected_unit, cell, TacticalFactionScript.Id.PLAYER
		)
		_last_log = res["log"]
		_skill_targeting = false
		_refresh_all()
		return

	var clicked := _board.unit_at(cell)
	if clicked != null:
		if clicked.faction == TacticalFactionScript.Id.PLAYER:
			_selected_unit = clicked
			_skill_targeting = false
			_refresh_all()
		return

	if _selected_unit != null and _selected_unit.faction == TacticalFactionScript.Id.PLAYER:
		if _board.try_move(_selected_unit, cell):
			_last_log = "%s 移动至 (%d,%d)" % [
				_selected_unit.def.display_name, cell.x, cell.y
			]
	_refresh_all()


func _on_end_turn_pressed() -> void:
	_clock.end_turn()
	if _clock.player_active:
		_board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	else:
		_board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	_skill_targeting = false
	_refresh_all()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
