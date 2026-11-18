extends SceneTree
## PC-75 GUI：万箭齐发侧格溅射 + 拖牌落到目标即结算。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc75_volley_fix_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-75-volley-fix.png"
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-75 volley fix")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC75 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	await create_timer(0.2).timeout

	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await process_frame
	await create_timer(0.35).timeout

	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	var board: TacticalBoard = sandbox._board
	var deck: TacticalCardDeck = sandbox._deck
	var archer: TacticalUnitInstance = null
	var foes: Array[TacticalUnitInstance] = []
	for u in board.living_units():
		if u.faction == TacticalFaction.Id.PLAYER and u.def.id == "archer":
			archer = u
		elif u.faction == TacticalFaction.Id.OPPONENT:
			foes.append(u)
	if archer == null or foes.size() < 3:
		push_error("PC75 capture: need archer + 3 foes")
		quit(1)
		return

	board.set_terrain_cells({})
	var park := 0
	for u in board.living_units():
		if u == archer or foes.has(u):
			continue
		u.cell = Vector2i(park % 6, 5)
		park += 1
	# 游侠 (1,2) 打 (3,2)；侧格 (3,1)/(3,3)。
	archer.cell = Vector2i(1, 2)
	foes[0].cell = Vector2i(3, 2)
	foes[1].cell = Vector2i(3, 1)
	foes[2].cell = Vector2i(3, 3)
	foes[0].hp = 99
	foes[1].hp = 99
	foes[2].hp = 99
	_vacate(board, Vector2i(4, 2))

	# 确保手牌有万箭齐发。
	var volley: TacticalActionCard = null
	for c in deck.hand:
		if c.kind == TacticalActionCard.Kind.SKILL_VOLLEY:
			volley = c
			break
	if volley == null:
		for c in deck.draw_pile:
			if c.kind == TacticalActionCard.Kind.SKILL_VOLLEY:
				volley = c
				break
		if volley != null:
			deck.draw_pile.erase(volley)
			deck.hand.append(volley)
	if volley == null:
		volley = TacticalActionCard.make_skill_volley("archer")
		deck.hand.append(volley)
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	await process_frame

	var splash := archer.effective_attack()
	var hp_mid_before := foes[0].hp
	var hp_l_before := foes[1].hp
	var hp_r_before := foes[2].hp

	# 模拟拖牌落到主目标格：自由打出 + 立刻结算。
	if not sandbox.capture_drop_first_card_on_unit("skill_volley", "archer"):
		push_error("PC75 capture: play volley failed")
		quit(1)
		return
	sandbox.call("_try_complete_aim_at_drop_cell", foes[0].cell)
	await process_frame
	await create_timer(0.85).timeout

	if foes[0].hp >= hp_mid_before:
		push_error("PC75 capture: primary not damaged")
		quit(1)
		return
	if foes[1].hp != hp_l_before - splash or foes[2].hp != hp_r_before - splash:
		push_error(
			"PC75 capture: side splash want -%d got L=%d R=%d"
			% [splash, hp_l_before - foes[1].hp, hp_r_before - foes[2].hp]
		)
		quit(1)
		return

	sandbox._last_log = "万箭齐发：主目标 + 垂直左右溅射"
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	sandbox._board_view._set_zoom(1.2)
	sandbox._board_view.recenter_camera()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC75 capture: viewport image null")
		quit(1)
		return
	var err := svp.save_png(out_path)
	if err != OK:
		push_error("PC75 capture: save_png failed %s" % err)
		quit(1)
		return
	print("PC75_VOLLEY_FIX_CAPTURE_OK %s mid=%d side=%d" % [out_path, foes[0].hp, foes[1].hp])
	quit(0)


func _vacate(board: TacticalBoard, cell: Vector2i) -> void:
	var u := board.unit_at(cell)
	if u != null:
		u.cell = Vector2i(5, 5)
