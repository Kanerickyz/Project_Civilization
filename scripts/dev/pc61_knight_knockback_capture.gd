extends SceneTree
## 盾卫击退 GUI 证据：攻击后目标沿方向被推开 1 格（位移 Tween）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc61_knight_knockback_capture.gd -- <out.png>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc-61-knight-knockback.png"
	DisplayServer.window_set_size(Vector2i(786, 1704))

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc61 capture: sandbox missing")
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
		push_error("pc61 capture: missing board/view")
		quit(1)
		return

	var knight: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFaction.Id.PLAYER and u.def.id == "knight":
			knight = u
		elif u.faction == TacticalFaction.Id.OPPONENT and foe == null:
			foe = u
		else:
			u.hp = 0
	if knight == null or foe == null:
		push_error("pc61 capture: need knight + foe")
		quit(1)
		return

	# 清空地形干扰；盾卫右打狼骑，击退落到空地。
	board.set_terrain_cells({})
	knight.cell = Vector2i(3, 4)
	foe.cell = Vector2i(4, 4)
	foe.hp = 99
	board.changed.emit()
	await create_timer(0.2, true, false, true).timeout

	var view_cam: Variant = view
	view_cam._set_zoom(1.55)
	view_cam._target = view_cam._cell_ground_center(Vector2i(4, 4), view.config.cell_size)
	view_cam._clamp_target()
	view_cam._apply_camera()

	await create_timer(0.25, true, false, true).timeout

	# 锁输入，避免 force_displace 的 changed 提前 refresh 把击退 Tween 提前播完。
	sandbox.set("_input_locked", true)
	var from := foe.cell
	var res: Dictionary = TacticalCombat.try_basic_attack(
		board, knight, foe.cell, TacticalFaction.Id.PLAYER, true
	)
	if not res.get("ok", false) or not res.get("knockback_moved", false):
		push_error("pc61 capture: expected free knockback, got %s" % res)
		quit(1)
		return

	# 攻击冲刺 + 受击 + 击退 Tween。
	var atk_tw: Tween = view.play_unit_attack(knight, from)
	if atk_tw != null:
		await atk_tw.finished
	view.play_damage_popup(from, int(res.get("damage", 0)))
	view.play_unit_hit(foe)
	sandbox._refresh_all()
	# 中后段截帧：可见推开过程（格间 Tween，非瞬移）。
	await create_timer(maxf(0.08, view.unit_move_duration_sec() * 0.65), true, false, true).timeout

	print("pc61 capture: knight@%s foe %s -> %s dmg=%s" % [knight.cell, from, foe.cell, res.get("damage")])

	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc61 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC61_KNIGHT_KNOCKBACK_CAPTURE_OK %s" % abs_path)
	quit(0)
