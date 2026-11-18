extends SceneTree
## PC-64 GUI：部署阶段全图站位 + 敌潜在点虚影 + 刺客/要员入队。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc64_assassin_deploy_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-64-assassin-deploy.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-64 assassin deploy")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC64 capture: sandbox missing")
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
	var has_assassin := false
	var has_vip := false
	for u in board.living_units():
		if u.def == null:
			continue
		if u.def.id == "assassin":
			has_assassin = true
			if not u.is_stealthed():
				push_error("PC64 capture: assassin should start stealthed")
				quit(1)
				return
		elif u.def.id == "devman":
			has_vip = true
	if not has_assassin or not has_vip:
		push_error("PC64 capture: missing assassin/devman on deploy board")
		quit(1)
		return
	if board.enemy_spawn_cells.size() != 6:
		push_error(
			"PC64 capture: expected 6 enemy spawn cells, got %d"
			% board.enemy_spawn_cells.size()
		)
		quit(1)
		return
	var opp := 0
	for u in board.living_units():
		if u.faction == TacticalFaction.Id.OPPONENT:
			opp += 1
	if opp != 0:
		push_error("PC64 capture: enemies must not spawn during deploy")
		quit(1)
		return

	sandbox._board_view._set_zoom(1.25)
	sandbox._board_view.recenter_camera()
	sandbox._refresh_all()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC64 capture: null board image")
		quit(1)
		return
	svp.save_png(out_path)
	print(
		"PC64_CAPTURE_OK assassin=%s vip=%s spawns=%d %s"
		% [has_assassin, has_vip, board.enemy_spawn_cells.size(), out_path]
	)
	quit(0)
