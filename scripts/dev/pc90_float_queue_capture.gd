extends SceneTree
## PC-90 GUI：同格 +攻/+血 串行队列——截在第二条弹出峰值（仅见 +血，证明未并行叠）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc90_float_queue_capture.gd -- <out.png>

const OUT_DEFAULT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-90-float-queue.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-90 float queue")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc90 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Node = packed.instantiate()
	root.add_child(sandbox)
	await create_timer(0.4, true, false, true).timeout
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(0.5, true, false, true).timeout

	var board: Variant = sandbox.get("_board")
	var view: Variant = sandbox.get("_board_view")
	if board == null or view == null:
		push_error("pc90 capture: missing board/view")
		quit(1)
		return

	var drum: TacticalUnitInstance = null
	var archer: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFaction.Id.PLAYER:
			u.hp = 0
			continue
		if u.def.id == "wardrum":
			drum = u
		elif u.def.id == "archer":
			archer = u
		else:
			u.hp = 0
	if drum == null or archer == null:
		push_error("pc90 capture: need wardrum+archer")
		quit(1)
		return

	board.set_terrain_cells({})
	drum.cell = Vector2i(2, 3)
	archer.cell = Vector2i(3, 3)
	board.changed.emit()
	await create_timer(0.2, true, false, true).timeout

	view._set_zoom(1.75)
	view._target = view._cell_ground_center(Vector2i(3, 3), view.config.cell_size)
	view._clamp_target()
	view._apply_camera()
	await create_timer(0.2, true, false, true).timeout

	# 同格两条：先 +1攻，再 +1血（间隔 0.4s）。
	view.play_passive_float_text(archer.cell, "+1攻", Color("ffe08a"))
	view.play_passive_float_text(archer.cell, "+1血", Color("7dff9a"))

	sandbox.set("_input_locked", true)
	sandbox.set("_last_log", "飘字队列 · +1攻 → +1血")
	var banner: Variant = sandbox.get("_turn_banner_panel")
	if banner != null:
		banner.modulate.a = 0.0
	sandbox.call("_refresh_all")

	# 0.4s 后第二条开始；再等 ~0.14s 到弹出峰值。
	await create_timer(0.54, true, false, true).timeout
	await process_frame
	await process_frame

	var img: Image = null
	if view.get("_viewport") != null:
		img = view._viewport.get_texture().get_image()
	if img == null:
		img = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc90 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC90_FLOAT_QUEUE_CAPTURE_OK %s" % abs_path)
	quit(0)
