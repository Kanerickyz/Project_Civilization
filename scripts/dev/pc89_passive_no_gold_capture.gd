extends SceneTree
## PC-89 GUI：被动触发无金色高亮（能力名 + 晃动/弹出 + 飘字）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc89_passive_no_gold_capture.gd -- <out.png>

const OUT_DEFAULT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-89-passive-no-gold.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-89 passive no gold")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc89 capture: sandbox missing")
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
		push_error("pc89 capture: missing board/view")
		quit(1)
		return

	var drum: TacticalUnitInstance = null
	var archer: TacticalUnitInstance = null
	var pekka: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFaction.Id.PLAYER:
			u.hp = 0
			continue
		if u.def.id == "wardrum":
			drum = u
		elif u.def.id == "archer":
			archer = u
		elif u.def.id == "mini_pekka":
			pekka = u
		else:
			u.hp = 0
	if drum == null or archer == null or pekka == null:
		push_error("pc89 capture: need wardrum+archer+pekka")
		quit(1)
		return

	board.set_terrain_cells({})
	drum.cell = Vector2i(2, 3)
	archer.cell = Vector2i(3, 3)
	pekka.cell = Vector2i(2, 4)
	board.changed.emit()
	await create_timer(0.2, true, false, true).timeout

	var view_cam: Variant = view
	view_cam._set_zoom(1.65)
	view_cam._target = view_cam._cell_ground_center(Vector2i(3, 3), view.config.cell_size)
	view_cam._clamp_target()
	view_cam._apply_camera()
	await create_timer(0.2, true, false, true).timeout

	var fx: Array = []
	var logs: Array = TacticalAbilitySystem.process_player_attack_card_played(board, fx)
	if fx.is_empty():
		push_error("pc89 capture: expected passive fx events, logs=%s" % [logs])
		quit(1)
		return
	var saw_owner_label := false
	var saw_buff := false
	for ev in fx:
		if not (ev is Dictionary):
			continue
		var text := str((ev as Dictionary).get("text", ""))
		var color: Color = (ev as Dictionary).get("color", Color.WHITE) as Color
		if text == "战鼓同频":
			saw_owner_label = true
			# 能力名不得再用金色。
			if color.r > 0.9 and color.g > 0.75 and color.b < 0.45:
				push_error("pc89 capture: owner label still gold color=%s" % [color])
				quit(1)
				return
		if text == "+1攻" or text == "+1血":
			saw_buff = true
	if not saw_owner_label or not saw_buff:
		push_error("pc89 capture: need owner label + buff fx, got %s" % [fx])
		quit(1)
		return

	sandbox.set("_input_locked", true)
	sandbox.set("_last_log", "被动触发 · %s" % "；".join(logs))
	var banner: Variant = sandbox.get("_turn_banner_panel")
	if banner != null:
		banner.modulate.a = 0.0
	if sandbox.has_method("_play_passive_fx"):
		sandbox.call("_play_passive_fx", fx)
	sandbox.call("_refresh_all")
	await create_timer(0.14, true, false, true).timeout
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
		push_error("pc89 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print(
		"PC89_PASSIVE_NO_GOLD_CAPTURE_OK fx=%d archer=%s/%s %s"
		% [fx.size(), archer.effective_attack(), archer.hp, abs_path]
	)
	quit(0)
