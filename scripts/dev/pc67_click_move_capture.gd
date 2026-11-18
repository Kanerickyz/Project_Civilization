extends SceneTree
## PC-67 GUI：点选己方显示绿格移力；无移动牌。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc67_click_move_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-67-click-move.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-67 click move")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC67 capture: sandbox missing")
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

	var deck: TacticalCardDeck = sandbox._deck
	if deck.count_kind(TacticalActionCard.Kind.MOVE) != 0:
		push_error("PC67 capture: MOVE cards must not be in deck")
		quit(1)
		return

	var knight: TacticalUnitInstance = null
	for u in sandbox._board.living_units():
		if u.faction == TacticalFaction.Id.PLAYER and u.def.id == "knight":
			knight = u
			break
	if knight == null:
		push_error("PC67 capture: missing knight")
		quit(1)
		return
	if knight.remaining_move_budget <= 0:
		push_error("PC67 capture: knight should have move budget after battle start")
		quit(1)
		return

	sandbox.capture_select_player_unit("knight")
	await process_frame
	await create_timer(0.15).timeout
	if sandbox._pending_kind != sandbox.PendingKind.MOVE:
		push_error("PC67 capture: selecting knight should enter MOVE pending")
		quit(1)
		return
	var greens: Array = sandbox._board.reachable_move_cells(knight)
	if greens.is_empty():
		push_error("PC67 capture: selected knight should show reachable greens")
		quit(1)
		return

	sandbox._board_view._set_zoom(1.2)
	sandbox._board_view.recenter_camera()
	sandbox._refresh_all()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC67 capture: null board image")
		quit(1)
		return
	svp.save_png(out_path)
	print(
		"PC67_CAPTURE_OK budget=%d greens=%d move_cards=%d %s"
		% [knight.remaining_move_budget, greens.size(), deck.count_kind(TacticalActionCard.Kind.MOVE), out_path]
	)
	quit(0)
