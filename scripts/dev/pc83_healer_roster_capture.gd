extends SceneTree
## PC-83 GUI：部署阶段可见医师（apothecary 剪纸）在可部署阵容。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc83_healer_roster_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-83-healer.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-83 healer roster")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC83 capture: sandbox missing")
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
	var has_healer := false
	var healer_cell := Vector2i(-1, -1)
	var players := 0
	var opponents := 0
	for u in board.living_units():
		if u.def == null:
			continue
		if u.faction == TacticalFaction.Id.PLAYER:
			players += 1
			if u.def.id == "healer":
				has_healer = true
				healer_cell = u.cell
				if u.def.max_hp != 4 or u.def.attack != 0 or u.def.attack_range != 2:
					push_error("PC83 capture: healer stats mismatch")
					quit(1)
					return
		elif u.faction == TacticalFaction.Id.OPPONENT:
			opponents += 1

	if not has_healer:
		push_error("PC83 capture: missing healer on board")
		quit(1)
		return
	if players != 6 or opponents != 6:
		push_error(
			"PC83 capture: expected 6+6 units, got players=%d opponents=%d"
			% [players, opponents]
		)
		quit(1)
		return

	# 选中医师以便棋盘高亮可辨认。
	if sandbox.has_method("capture_select_player_unit"):
		sandbox.capture_select_player_unit("healer")
	else:
		for u2 in board.living_units():
			if u2.faction == TacticalFaction.Id.PLAYER and u2.def.id == "healer":
				sandbox._selected_unit = u2
				break

	sandbox._board_view._set_zoom(1.15)
	sandbox._board_view.recenter_camera()
	sandbox._refresh_all()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC83 capture: null board image")
		quit(1)
		return
	svp.save_png(out_path)
	print(
		"PC83_CAPTURE_OK healer_cell=%s players=%d opponents=%d %s"
		% [str(healer_cell), players, opponents, out_path]
	)
	quit(0)
