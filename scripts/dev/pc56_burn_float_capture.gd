extends SceneTree
## PC-56 GUI：段开始燃烧扣血飘字。用法：godot --path . --display-driver x11 --script res://scripts/dev/pc56_burn_float_capture.gd

const OUT_PATH := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-56-burn-float.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-56 burn float")
	var sandbox: Control = load("res://scenes/main/sandbox.tscn").instantiate()
	root.add_child(sandbox)
	# 跳过部署，进入玩家段（段开始会结算燃烧）。
	await process_frame
	await process_frame
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(1.6).timeout
	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	var target: TacticalUnitInstance = null
	for u in sandbox._board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			target = u
			break
	if target == null:
		push_error("PC56 capture: no opponent unit")
		quit(1)
		return
	# 挪到盘面中央，避免飘字贴 SubViewport 右缘被裁切。
	target.cell = Vector2i(3, 2)
	target.add_burn_stacks(3)
	sandbox._board.changed.emit()
	sandbox._refresh_all()
	await create_timer(0.2).timeout

	# 与段开始同一逻辑：process_burn_ticks(本方) → 飘字/闪白；截在飘字峰值。
	var events: Array = sandbox._board.process_burn_ticks(TacticalFactionScript.Id.OPPONENT)
	if events.is_empty():
		push_error("PC56 capture: expected burn tick events")
		quit(1)
		return
	var ev: Dictionary = events[0]
	var cell: Vector2i = ev.get("cell", target.cell)
	var dmg := int(ev.get("damage", 0))
	sandbox._board_view.play_damage_popup(cell, dmg)
	sandbox._board_view.play_unit_hit(target)
	sandbox._refresh_all()
	await create_timer(0.12).timeout
	await process_frame
	await process_frame

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC56 capture: null board image")
		quit(1)
		return
	svp.save_png(OUT_PATH)
	print("PC56_CAPTURE_OK dmg=%d %s" % [dmg, OUT_PATH])
	quit(0)
