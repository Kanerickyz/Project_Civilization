extends SceneTree
## PC-98 GUI：约 8×8 不规则边缘缩进预览（部署阶段）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc98_irregular_edge_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-98-irregular-edge-preview.png"
const BoardEdgeShapeScript := preload("res://scripts/map/board_edge_shape.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-98 irregular edge")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC98 capture: sandbox missing")
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
	if board.grid_width != 8 or board.grid_height != 8:
		push_error(
			"PC98 capture: expected 8x8 board, got %dx%d"
			% [board.grid_width, board.grid_height]
		)
		quit(1)
		return

	var voids := BoardEdgeShapeScript.void_cells(8, 8)
	if voids.is_empty():
		push_error("PC98 capture: expected non-empty void mask")
		quit(1)
		return
	for cell in voids:
		if board.is_present(cell):
			push_error("PC98 capture: void cell still present %s" % str(cell))
			quit(1)
			return
		if board.is_passable(cell):
			push_error("PC98 capture: void cell passable %s" % str(cell))
			quit(1)
			return
	# 角落应缺格；中腹应在盘。
	if board.is_present(Vector2i(0, 0)) or board.is_present(Vector2i(7, 7)):
		push_error("PC98 capture: corners should be void")
		quit(1)
		return
	if not board.is_present(Vector2i(3, 3)):
		push_error("PC98 capture: center should be present")
		quit(1)
		return

	var players := 0
	var opponents := 0
	for u in board.living_units():
		if not board.is_present(u.cell):
			push_error("PC98 capture: unit on void %s @ %s" % [u.def.id, str(u.cell)])
			quit(1)
			return
		if u.faction == TacticalFaction.Id.PLAYER:
			players += 1
			if u.cell.x >= 4:
				push_error("PC98 capture: player outside left half %s" % str(u.cell))
				quit(1)
				return
		elif u.faction == TacticalFaction.Id.OPPONENT:
			opponents += 1
			if u.cell.x < 4:
				push_error("PC98 capture: enemy outside right half %s" % str(u.cell))
				quit(1)
				return

	if players != 6 or opponents != 6:
		push_error(
			"PC98 capture: expected 6+6 units, got players=%d opponents=%d"
			% [players, opponents]
		)
		quit(1)
		return

	# 缩到看全盘，便于预览边缘缩进轮廓。
	sandbox._board_view._set_zoom(sandbox._board_view._effective_zoom_min() * 1.05)
	sandbox._board_view.recenter_camera()
	sandbox._refresh_all()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout

	var img: Image = sandbox._board_view._viewport.get_texture().get_image()
	if img == null:
		push_error("PC98 capture: null board viewport image")
		quit(1)
		return
	var err := img.save_png(out_path)
	if err != OK:
		push_error("PC98 capture: save_png failed %s err=%s" % [out_path, err])
		quit(1)
		return
	print(
		"PC98_CAPTURE_OK board=8x8 voids=%d present=%d players=%d opponents=%d %s"
		% [voids.size(), 64 - voids.size(), players, opponents, out_path]
	)
	quit(0)
