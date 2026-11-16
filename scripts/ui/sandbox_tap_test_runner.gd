extends SceneTree
## 竖屏沙盘真实输入链路：沙盘挂在 393×852 SubViewport，经 push_input 注入触摸/鼠标，
## 点格须经 GUI 到达 GridBoardView 并选中正确单位（棋盘在竖屏有 offset_top，可暴露二次局部化）。


const SANDBOX_SCENE := "res://scenes/main/sandbox.tscn"

var _vp: SubViewport


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(393, 852)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var packed: PackedScene = load(SANDBOX_SCENE)
	var sandbox: Control = packed.instantiate()
	_vp.add_child(sandbox)
	for i in 6:
		await process_frame
	var view = sandbox.get("_board_view")
	if view.get_global_rect().position.y <= 0.0:
		push_error("SandboxTap: portrait board should sit below the top HUD (offset_top > 0)")
		quit(1)
		return
	var ok := true
	ok = await _check_tap(sandbox, "touch", "touch") and ok
	ok = await _check_tap(sandbox, "mouse", "mouse") and ok
	ok = await _check_tap(sandbox, "touch+emulated-mouse", "both") and ok
	if ok:
		print("SANDBOX_TAP_OK")
	quit(0 if ok else 1)


func _check_tap(sandbox: Control, tag: String, mode: String) -> bool:
	sandbox.set("_selected_unit", null)
	var board = sandbox.get("_board")
	var view = sandbox.get("_board_view")
	var rect: Rect2 = view.get_global_rect().grow(-4.0)
	var target: TacticalUnitInstance = null
	for u in board.living_units():
		if rect.has_point(_cell_global(view, u.cell)):
			target = u
			break
	if target == null:
		push_error("SandboxTap[%s]: no unit visible inside board rect" % tag)
		return false
	var gpos: Vector2 = _cell_global(view, target.cell)
	var hits: Array = []
	var cb := func(c: Vector2i) -> void: hits.append(c)
	view.cell_clicked.connect(cb)
	if mode == "touch" or mode == "both":
		_send_touch(gpos, true)
	if mode == "mouse" or mode == "both":
		_send_mouse(gpos, true, mode == "both")
	await process_frame
	if mode == "touch" or mode == "both":
		_send_touch(gpos, false)
	if mode == "mouse" or mode == "both":
		_send_mouse(gpos, false, mode == "both")
	for i in 3:
		await process_frame
	view.cell_clicked.disconnect(cb)
	if hits != [target.cell]:
		push_error("SandboxTap[%s]: tap at %s should emit exactly [%s], got %s" % [tag, gpos, target.cell, hits])
		return false
	if sandbox.get("_selected_unit") != target:
		push_error("SandboxTap[%s]: tap should select unit at %s" % [tag, target.cell])
		return false
	return true


func _cell_global(view, cell: Vector2i) -> Vector2:
	var world: Vector2 = view._cell_to_world(cell, view.config.cell_size)
	var vp_pos: Vector2 = view._camera.get_canvas_transform() * world
	var cs: Vector2 = view._viewport_container.size
	var vs: Vector2i = view._viewport.size
	var local := Vector2(vp_pos.x * cs.x / float(vs.x), vp_pos.y * cs.y / float(vs.y))
	return view.get_global_transform_with_canvas() * local


func _send_touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	_vp.push_input(ev)


func _send_mouse(pos: Vector2, pressed: bool, emulated: bool) -> void:
	var ev := InputEventMouseButton.new()
	if emulated:
		ev.device = InputEvent.DEVICE_ID_EMULATION
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_vp.push_input(ev)
