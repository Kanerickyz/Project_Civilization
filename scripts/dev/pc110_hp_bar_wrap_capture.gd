extends SceneTree
## PC-110 GUI：血条一行最多 6 段、超出换行截图（目标单位 max_hp > 6）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc110_hp_bar_wrap_capture.gd -- <out.png>

const OUT_DEFAULT := (
	"/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-110-hp-bar-wrap.png"
)
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const HP_SEG_PER_ROW := 6


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-110 HP bar wrap")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc110 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Node = packed.instantiate()
	root.add_child(sandbox)
	await create_timer(0.45, true, false, true).timeout
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(0.55, true, false, true).timeout

	var board: Variant = sandbox.get("_board")
	var view: Variant = sandbox.get("_board_view")
	if board == null or view == null:
		push_error("pc110 capture: missing board/view")
		quit(1)
		return

	# 盾卫 max_hp=10 → 两行（6+4）；并叠甲证明甲段也在条下。
	var focus: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def != null and u.def.id == "knight":
			focus = u
			break
	if focus == null:
		push_error("pc110 capture: need knight (>6 HP)")
		quit(1)
		return

	focus.cell = Vector2i(2, 3)
	focus.hp = focus.effective_max_hp()
	focus.armor = 2
	# 明示 10 血：6+4 两行；甲 2 段在血条下方。
	if focus.effective_max_hp() <= HP_SEG_PER_ROW:
		push_error(
			"pc110 capture: knight max_hp=%d not > %d" % [focus.effective_max_hp(), HP_SEG_PER_ROW]
		)
		quit(1)
		return
	# 其他单位藏到边角；截图只突出盾卫换行血条。
	var park_y := 0
	for u in board.living_units():
		if u == focus:
			continue
		u.cell = Vector2i(0, park_y)
		park_y += 1
	board.changed.emit()
	await create_timer(0.25, true, false, true).timeout

	if not _assert_hp_bar_wrap(view, focus):
		quit(1)
		return

	_hide_hud_for_shot(sandbox)
	view._set_zoom(view.config.camera_zoom_max)
	view._target = view._cell_ground_center(focus.cell, view.config.cell_size)
	view._clamp_target()
	view._apply_camera()
	var segs_n: Node = (view._hp_bars[focus] as Control).get_node("Segments")
	print(
		"pc110 focus rows=%d max_hp=%d armor=%d row_ys=%s,%s"
		% [
			segs_n.get_child_count(),
			focus.effective_max_hp(),
			focus.armor,
			(segs_n.get_child(0) as Control).position.y,
			(segs_n.get_child(1) as Control).position.y,
		]
	)

	await create_timer(0.85, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc110 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC110_HP_BAR_WRAP_CAPTURE_OK %s" % abs_path)
	quit(0)


func _assert_hp_bar_wrap(view: Variant, unit: TacticalUnitInstance) -> bool:
	if unit == null or not view._hp_bars.has(unit):
		push_error("pc110 capture: missing hp bar")
		return false
	var root: Control = view._hp_bars[unit] as Control
	var legacy: Label = root.get_node_or_null("Text") as Label
	if legacy != null and (legacy.visible or not str(legacy.text).is_empty()):
		push_error("pc110 capture: legacy HP/ATK text still present")
		return false
	var segs: Node = root.get_node_or_null("Segments")
	if segs == null or segs.get_child_count() < 2:
		push_error(
			"pc110 capture: expected >=2 HP rows for max_hp=%d (got %d)"
			% [unit.effective_max_hp(), 0 if segs == null else segs.get_child_count()]
		)
		return false
	var row0: Node = segs.get_child(0)
	if row0.get_child_count() != HP_SEG_PER_ROW:
		push_error(
			"pc110 capture: first row should have %d pips, got %d"
			% [HP_SEG_PER_ROW, row0.get_child_count()]
		)
		return false
	var expected_rows := int(ceili(float(unit.effective_max_hp()) / float(HP_SEG_PER_ROW)))
	if segs.get_child_count() != expected_rows:
		push_error(
			"pc110 capture: expected %d rows, got %d"
			% [expected_rows, segs.get_child_count()]
		)
		return false
	var row1: Node = segs.get_child(1)
	var expected_tail := unit.effective_max_hp() - HP_SEG_PER_ROW
	if row1.get_child_count() != expected_tail:
		push_error(
			"pc110 capture: second row should have %d pips, got %d"
			% [expected_tail, row1.get_child_count()]
		)
		return false
	var armor_box: Node = root.get_node_or_null("ArmorSegments")
	if armor_box == null or not (armor_box as CanvasItem).visible:
		push_error("pc110 capture: expected visible armor segments")
		return false
	var armor_pips := 0
	for row in armor_box.get_children():
		armor_pips += row.get_child_count()
	if armor_pips != unit.armor:
		push_error("pc110 capture: armor pips=%d want %d" % [armor_pips, unit.armor])
		return false
	# 多行须垂直错开（修过 Container 未设 size 时会叠在一起）。
	var y0 := (row0 as Control).position.y
	var y1 := (row1 as Control).position.y
	if y1 <= y0 + 0.5:
		push_error("pc110 capture: HP rows not vertically separated (y0=%s y1=%s)" % [y0, y1])
		return false
	return true


func _hide_hud_for_shot(sandbox: Node) -> void:
	if sandbox.get("_hand_fan") != null:
		(sandbox.get("_hand_fan") as CanvasItem).visible = false
	if sandbox.get("_end_turn_button") != null:
		(sandbox.get("_end_turn_button") as CanvasItem).visible = false
	if sandbox.get("_cancel_target_button") != null:
		(sandbox.get("_cancel_target_button") as CanvasItem).visible = false
	if sandbox.get("_bottom_bar") != null:
		(sandbox.get("_bottom_bar") as CanvasItem).visible = false
	if sandbox.get("_side_panel") != null:
		(sandbox.get("_side_panel") as CanvasItem).visible = false
