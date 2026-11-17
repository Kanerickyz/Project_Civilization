extends SceneTree
## PC-37 GUI：伤害飘字 + 受击闪白。用法：godot --path . --display-driver x11 --script res://scripts/dev/pc37_damage_float_flash_capture.gd

const OUT_PATH := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc37-damage-float-flash.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-37 damage float + hit flash")
	var sandbox: Control = load("res://scenes/main/sandbox.tscn").instantiate()
	root.add_child(sandbox)
	# 等开局回合横幅淡出后再打受击反馈。
	await create_timer(2.2).timeout
	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0
	var target: TacticalUnitInstance = null
	for u in sandbox._board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			target = u
			break
	if target == null:
		push_error("PC37 capture: no opponent unit")
		quit(1)
		return
	# 挪到盘面中央，避免飘字贴 SubViewport 右缘被裁切。
	target.cell = Vector2i(3, 2)
	sandbox._board.changed.emit()
	sandbox._refresh_all()
	await create_timer(0.2).timeout
	var dmg := 7
	sandbox._board_view.play_damage_popup(target.cell, dmg)
	sandbox._board_view.play_unit_hit(target)
	await create_timer(0.12).timeout
	await process_frame
	await process_frame
	# 棋盘 SubViewport：飘字/闪白最清晰（整窗竖屏里盘面较小）。
	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC37 capture: null board image")
		quit(1)
		return
	svp.save_png(OUT_PATH)
	print("PC37_CAPTURE_OK %s" % OUT_PATH)
	quit(0)
