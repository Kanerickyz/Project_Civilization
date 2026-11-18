extends SceneTree
## PC-58：游侠最小射程红圈 + 鼓手鼓舞叠狂暴角标截图。


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc58_ranger_inspire.png"
	var w := int(args[1]) if args.size() > 1 else 393
	var h := int(args[2]) if args.size() > 2 else 852
	DisplayServer.window_set_size(Vector2i(w, h))
	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc58 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Node = packed.instantiate()
	root.add_child(sandbox)
	await create_timer(0.4, true, false, true).timeout
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(0.45, true, false, true).timeout

	var board: Variant = sandbox.get("_board")
	if board == null:
		push_error("pc58 capture: no board")
		quit(1)
		return

	var archer: TacticalUnitInstance = null
	var drum: TacticalUnitInstance = null
	var ally: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFaction.Id.PLAYER:
			continue
		if u.def.id == "archer":
			archer = u
		elif u.def.id == "wardrum":
			drum = u
		elif ally == null:
			ally = u
	if archer == null or drum == null or ally == null:
		push_error("pc58 capture: missing archer/wardrum/ally")
		quit(1)
		return

	# 把友方贴到鼓手旁，打出鼓舞叠狂暴。
	ally.cell = drum.cell + Vector2i(1, 0)
	var inspire_res: Dictionary = board.apply_inspire_frenzy(drum, 1)
	if int(inspire_res.get("buffed", 0)) < 1:
		push_error("pc58 capture: inspire did not buff neighbor")
		quit(1)
		return

	# 选中游侠并授权攻击，展示最小射程红圈（不含邻格）。
	if sandbox.has_method("capture_select_player_unit"):
		sandbox.capture_select_player_unit("archer")
	sandbox.set("_focus_unit", archer)
	sandbox.set("_selected_unit", archer)
	var deck: Variant = sandbox.get("_deck")
	if deck != null and deck.has_method("authorize_attack"):
		deck.authorize_attack(archer)
	# PendingKind { NONE, MOVE, ATTACK } → ATTACK = 2
	sandbox.set("_pending_kind", 2)
	sandbox.set("_last_log", "游侠射 2–3 · 鼓手鼓舞叠狂暴")
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	await create_timer(0.45, true, false, true).timeout

	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc58 capture: save failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print(
		"PC58_CAPTURE_OK ",
		abs_path,
		" archer_min=",
		archer.def.attack_range_min,
		" ally_frenzy=",
		ally.frenzy_stacks
	)
	quit(0)
