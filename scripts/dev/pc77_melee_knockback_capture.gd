extends SceneTree
## PC-77 GUI 证据：近战击退中段；远程不推。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc77_melee_knockback_capture.gd -- <out.png>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc-77-melee-knockback.png"
	DisplayServer.window_set_size(Vector2i(786, 1704))

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc77 capture: sandbox missing")
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
		push_error("pc77 capture: missing board/view")
		quit(1)
		return

	var pekka: TacticalUnitInstance = null
	var archer: TacticalUnitInstance = null
	var foe_melee: TacticalUnitInstance = null
	var foe_ranged: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFaction.Id.PLAYER and u.def.id == "mini_pekka":
			pekka = u
		elif u.faction == TacticalFaction.Id.PLAYER and u.def.id == "archer":
			archer = u
		elif u.faction == TacticalFaction.Id.OPPONENT:
			if foe_melee == null:
				foe_melee = u
			elif foe_ranged == null:
				foe_ranged = u
			else:
				u.hp = 0
		else:
			u.hp = 0
	if pekka == null or archer == null or foe_melee == null or foe_ranged == null:
		push_error("pc77 capture: need pekka+archer+2 foes")
		quit(1)
		return

	board.set_terrain_cells({})
	# 大剑邻格右推；游侠在左侧远距瞄准另一狼骑（不推）。
	pekka.cell = Vector2i(3, 4)
	foe_melee.cell = Vector2i(4, 4)
	archer.cell = Vector2i(1, 2)
	foe_ranged.cell = Vector2i(4, 2)
	foe_melee.hp = 99
	foe_ranged.hp = 99
	_vacate(board, Vector2i(5, 4))
	_vacate(board, Vector2i(5, 2))
	board.changed.emit()
	await create_timer(0.2, true, false, true).timeout

	# 远程先打：应不位移。
	var ranged_from := foe_ranged.cell
	var ranged_res: Dictionary = TacticalCombat.try_basic_attack(
		board, archer, foe_ranged.cell, TacticalFaction.Id.PLAYER, true
	)
	if not ranged_res.get("ok", false):
		push_error("pc77 capture: ranged attack failed %s" % ranged_res)
		quit(1)
		return
	if ranged_res.get("knockback_moved", false) or foe_ranged.cell != ranged_from:
		push_error("pc77 capture: ranged must not knockback, got %s cell=%s" % [ranged_res, foe_ranged.cell])
		quit(1)
		return

	var view_cam: Variant = view
	view_cam._set_zoom(1.55)
	view_cam._target = view_cam._cell_ground_center(Vector2i(4, 4), view.config.cell_size)
	view_cam._clamp_target()
	view_cam._apply_camera()
	await create_timer(0.25, true, false, true).timeout

	sandbox.set("_input_locked", true)
	var from := foe_melee.cell
	var res: Dictionary = TacticalCombat.try_basic_attack(
		board, pekka, foe_melee.cell, TacticalFaction.Id.PLAYER, true
	)
	if not res.get("ok", false) or not res.get("knockback_moved", false):
		push_error("pc77 capture: expected melee knockback from pekka, got %s" % res)
		quit(1)
		return

	var atk_tw: Tween = view.play_unit_attack(pekka, from)
	if atk_tw != null:
		await atk_tw.finished
	view.play_damage_popup(from, int(res.get("damage", 0)))
	view.play_unit_hit(foe_melee)
	sandbox._refresh_all()
	await create_timer(maxf(0.08, view.unit_move_duration_sec() * 0.65), true, false, true).timeout

	print(
		"pc77 capture: melee %s->%s; ranged stayed %s"
		% [from, foe_melee.cell, foe_ranged.cell]
	)

	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc77 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC77_MELEE_KNOCKBACK_CAPTURE_OK %s" % abs_path)
	quit(0)


func _vacate(board: Variant, cell: Vector2i) -> void:
	var u: TacticalUnitInstance = board.unit_at(cell)
	if u != null:
		u.hp = 0
