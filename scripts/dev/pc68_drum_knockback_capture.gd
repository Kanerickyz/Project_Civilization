extends SceneTree
## PC-68 GUI 证据：非盾卫击退中段 + 鼓手邻格友方（攻牌被动语境）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc68_drum_knockback_capture.gd -- <out.png>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc-68-drum-knockback.png"
	DisplayServer.window_set_size(Vector2i(786, 1704))

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc68 capture: sandbox missing")
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
		push_error("pc68 capture: missing board/view")
		quit(1)
		return

	var pekka: TacticalUnitInstance = null
	var drum: TacticalUnitInstance = null
	var archer: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFaction.Id.PLAYER and u.def.id == "mini_pekka":
			pekka = u
		elif u.faction == TacticalFaction.Id.PLAYER and u.def.id == "wardrum":
			drum = u
		elif u.faction == TacticalFaction.Id.PLAYER and u.def.id == "archer":
			archer = u
		elif u.faction == TacticalFaction.Id.OPPONENT and foe == null:
			foe = u
		else:
			u.hp = 0
	if pekka == null or drum == null or archer == null or foe == null:
		push_error("pc68 capture: need pekka+wardrum+archer+foe")
		quit(1)
		return

	board.set_terrain_cells({})
	# 鼓手邻格友方可读；大剑右打狼骑击退。
	drum.cell = Vector2i(2, 3)
	archer.cell = Vector2i(3, 3)
	pekka.cell = Vector2i(3, 4)
	foe.cell = Vector2i(4, 4)
	foe.hp = 99
	board.changed.emit()
	await create_timer(0.2, true, false, true).timeout

	# 模拟打出攻击牌：鼓手邻格 +1/+1（游侠已无出牌抽牌被动）。
	TacticalAbilitySystem.process_player_attack_card_played(board)
	board.changed.emit()

	var view_cam: Variant = view
	view_cam._set_zoom(1.55)
	view_cam._target = view_cam._cell_ground_center(Vector2i(4, 4), view.config.cell_size)
	view_cam._clamp_target()
	view_cam._apply_camera()
	await create_timer(0.25, true, false, true).timeout

	sandbox.set("_input_locked", true)
	var from := foe.cell
	var res: Dictionary = TacticalCombat.try_basic_attack(
		board, pekka, foe.cell, TacticalFaction.Id.PLAYER, true
	)
	if not res.get("ok", false) or not res.get("knockback_moved", false):
		push_error("pc68 capture: expected free knockback from pekka, got %s" % res)
		quit(1)
		return

	var atk_tw: Tween = view.play_unit_attack(pekka, from)
	if atk_tw != null:
		await atk_tw.finished
	view.play_damage_popup(from, int(res.get("damage", 0)))
	view.play_unit_hit(foe)
	sandbox._refresh_all()
	await create_timer(maxf(0.08, view.unit_move_duration_sec() * 0.65), true, false, true).timeout

	print(
		"pc68 capture: pekka@%s foe %s -> %s archer atk=%s hp=%s"
		% [pekka.cell, from, foe.cell, archer.effective_attack(), archer.hp]
	)

	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc68 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC68_DRUM_KNOCKBACK_CAPTURE_OK %s" % abs_path)
	quit(0)
