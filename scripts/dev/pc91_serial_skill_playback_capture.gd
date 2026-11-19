extends SceneTree
## PC-91 GUI：猎召反应攻击串行——截在第二段出击冲刺峰值（可见猎召飘字，非瞬间团灭）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc91_serial_skill_playback_capture.gd -- <out.png>

const OUT_DEFAULT := (
	"/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-91-serial-skill-playback.png"
)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-91 serial skill playback")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc91 capture: sandbox missing")
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
		push_error("pc91 capture: missing board/view")
		quit(1)
		return

	var archer: TacticalUnitInstance = null
	var knight: TacticalUnitInstance = null
	var pekka: TacticalUnitInstance = null
	var foe_a: TacticalUnitInstance = null
	var foe_b: TacticalUnitInstance = null
	var foe_c: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFaction.Id.PLAYER:
			match u.def.id:
				"archer":
					archer = u
				"knight":
					knight = u
				"mini_pekka":
					pekka = u
				_:
					u.hp = 0
		else:
			if foe_a == null:
				foe_a = u
			elif foe_b == null:
				foe_b = u
			elif foe_c == null:
				foe_c = u
			else:
				u.hp = 0
	if archer == null or knight == null or pekka == null or foe_a == null or foe_b == null:
		push_error("pc91 capture: need archer+knight+pekka+2 foes")
		quit(1)
		return

	board.set_terrain_cells({})
	# 游侠击杀 foe_a → 猎召：邻格盾卫打 foe_b，大剑打 foe_c（两段串行）。
	archer.cell = Vector2i(2, 2)
	knight.cell = Vector2i(3, 2)
	pekka.cell = Vector2i(2, 3)
	foe_a.cell = Vector2i(4, 2)
	foe_b.cell = Vector2i(3, 3)
	if foe_c != null:
		foe_c.cell = Vector2i(2, 4)
		foe_c.hp = 8
	foe_a.hp = 1
	foe_b.hp = 8
	board.changed.emit()
	await create_timer(0.2, true, false, true).timeout

	view._set_zoom(1.65)
	view._target = view._cell_ground_center(Vector2i(3, 3), view.config.cell_size)
	view._clamp_target()
	view._apply_camera()
	await create_timer(0.2, true, false, true).timeout

	var res: Dictionary = board.apply_damage(foe_a, 99, archer)
	var fx: Array = res.get("passive_fx", []) as Array
	var reactions := 0
	for ev in fx:
		if ev is Dictionary and str((ev as Dictionary).get("kind", "")) == "reaction_attack":
			reactions += 1
	if reactions < 1:
		push_error("pc91 capture: expected reaction_attack in fx, got %s" % [fx])
		quit(1)
		return

	sandbox.set("_input_locked", true)
	sandbox.set("_last_log", "猎召串行 · %d 段出击" % reactions)
	var banner: Variant = sandbox.get("_turn_banner_panel")
	if banner != null:
		banner.modulate.a = 0.0
	sandbox.call("_refresh_all")
	await process_frame

	# 异步串行播放；截在第一段冲刺中段（约 tag 弹出后 + 冲刺 0.09s）。
	sandbox.call("_play_skill_fx_async", fx)
	await create_timer(0.12, true, false, true).timeout
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
		push_error("pc91 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC91_SERIAL_SKILL_CAPTURE_OK %s reactions=%d" % [abs_path, reactions])
	quit(0)
