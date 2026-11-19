extends SceneTree
## PC-66 GUI：6×6 棋盘 · 左半部署 · 敌方开局在场 · 无缩圈/要员。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc66_board_6x6_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-66-board-6x6.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-66 board 6x6")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC66 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	await create_timer(0.35).timeout

	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	var board: TacticalBoard = sandbox._board
	if board.grid_width != 6 or board.grid_height != 6:
		push_error(
			"PC66 capture: expected 6x6 board, got %dx%d"
			% [board.grid_width, board.grid_height]
		)
		quit(1)
		return

	var players := 0
	var opponents := 0
	for u in board.living_units():
		if u.def == null:
			continue
		if u.def.id == "devman":
			push_error("PC66 capture: devman must not be on board")
			quit(1)
			return
		if u.def.id == "assassin":
			push_error("PC66 capture: assassin must not be on deployable roster")
			quit(1)
			return
		if u.faction == TacticalFaction.Id.PLAYER:
			players += 1
			if u.cell.x >= 3:
				push_error("PC66 capture: player outside left half %s" % str(u.cell))
				quit(1)
				return
		elif u.faction == TacticalFaction.Id.OPPONENT:
			opponents += 1
			if u.cell.x < 3:
				push_error("PC66 capture: enemy outside right half %s" % str(u.cell))
				quit(1)
				return

	if players != 6 or opponents != 6:
		push_error(
			"PC66 capture: expected 6+6 units, got players=%d opponents=%d"
			% [players, opponents]
		)
		quit(1)
		return
	if board.is_player_deploy_cell(Vector2i(3, 0)):
		push_error("PC66 capture: right half must not be deploy zone")
		quit(1)
		return
	if not board.is_player_deploy_cell(Vector2i(0, 0)):
		push_error("PC66 capture: left half should be deploy zone")
		quit(1)
		return

	sandbox._board_view._set_zoom(1.15)
	sandbox._board_view.recenter_camera()
	sandbox._refresh_all()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC66 capture: null board image")
		quit(1)
		return
	svp.save_png(out_path)
	print(
		"PC66_CAPTURE_OK board=6x6 players=%d opponents=%d %s"
		% [players, opponents, out_path]
	)
	quit(0)
