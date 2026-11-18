extends SceneTree
## PC-73 GUI：盾卫冲撞瞄准红圈 + 路径单位。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc73_knight_charge_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-73-knight-charge.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-73 knight charge")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC73 capture: sandbox missing")
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
	var knight: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFaction.Id.PLAYER and u.def.id == "knight":
			knight = u
		elif u.faction == TacticalFaction.Id.OPPONENT and foe == null:
			foe = u
	if knight == null or foe == null:
		push_error("PC73 capture: need knight + foe")
		quit(1)
		return

	# 摆冲撞轴：盾卫 → 敌 → 空 → 空。
	var park_i := 0
	for u in board.living_units():
		u.cell = Vector2i(park_i % board.grid_width, board.grid_height - 1)
		park_i += 1
	board.set_terrain_cells({})
	knight.cell = Vector2i(1, 2)
	foe.cell = Vector2i(2, 2)
	foe.hp = 99

	# 手牌确保有冲撞。
	var charge: TacticalActionCard = null
	for c in deck.hand:
		if c.kind == TacticalActionCard.Kind.SKILL_CHARGE:
			charge = c
			break
	if charge == null:
		for c in deck.draw_pile:
			if c.kind == TacticalActionCard.Kind.SKILL_CHARGE:
				charge = c
				break
		if charge != null:
			deck.draw_pile.erase(charge)
			deck.hand.append(charge)
	if charge == null:
		charge = TacticalActionCard.make_skill_charge("knight")
		deck.hand.append(charge)

	if not sandbox.capture_drop_first_card_on_unit("skill_charge", "knight"):
		push_error("PC73 capture: play charge failed")
		quit(1)
		return
	if sandbox._pending_kind != sandbox.PendingKind.CHARGE:
		push_error("PC73 capture: expected CHARGE aim")
		quit(1)
		return

	sandbox._board_view._set_zoom(1.2)
	sandbox._board_view.recenter_camera()
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	await process_frame
	await process_frame
	await create_timer(0.3).timeout

	var overlay_n: int = sandbox._board_view._overlay_attack.size()
	if overlay_n <= 0:
		push_error("PC73 capture: expected charge direction overlay")
		quit(1)
		return

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC73 capture: null board image")
		quit(1)
		return
	svp.save_png(out_path)
	print("PC73_KNIGHT_CHARGE_CAPTURE_OK overlay=%d %s" % [overlay_n, out_path])
	quit(0)
