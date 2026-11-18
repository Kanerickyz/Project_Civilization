extends SceneTree
## 敌方狼骑兵点选：行动格 + 下回合意图虚影 GUI 证据。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc60_wolf_intent_preview_capture.gd -- <out.png>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc-60-wolf-intent-preview.png"
	DisplayServer.window_set_size(Vector2i(786, 1704))

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc60 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Node = packed.instantiate()
	root.add_child(sandbox)
	await create_timer(0.4, true, false, true).timeout
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(0.45, true, false, true).timeout

	var board: Variant = sandbox.get("_board")
	var view: Variant = sandbox.get("_board_view")
	if board == null or view == null:
		push_error("pc60 capture: missing board/view")
		quit(1)
		return

	var rider: TacticalUnitInstance = null
	var player: TacticalUnitInstance = null
	for u in board.living_units():
		if TacticalEnemyAi.uses_behavior_sm(u) and rider == null:
			rider = u
		elif u.faction == TacticalFaction.Id.PLAYER and player == null:
			player = u
		else:
			u.hp = 0
	if rider == null or player == null:
		push_error("pc60 capture: missing rider/player")
		quit(1)
		return

	# 拉开距离强制「移动」意图虚影（路径线 + 落点半透明）。
	player.cell = Vector2i(2, 4)
	rider.cell = Vector2i(7, 4)
	rider.next_intent = TacticalEnemyAi.Intent.MOVE
	rider.remaining_move_budget = 0
	board.changed.emit()

	var preview: Dictionary = TacticalEnemyAi.preview_next_action(board, rider)
	if String(preview.get("kind", "")) != "move":
		push_error("pc60 capture: expected move preview, got %s" % preview.get("kind", ""))
		quit(1)
		return

	if not sandbox.capture_select_opponent_rider():
		push_error("pc60 capture: select rider failed")
		quit(1)
		return

	# 镜头对准路径中点，放大看清虚影。
	var dest: Vector2i = preview.get("to", rider.cell) as Vector2i
	var mid := Vector2i(
		int(round((float(rider.cell.x) + float(dest.x)) * 0.5)),
		int(round((float(rider.cell.y) + float(dest.y)) * 0.5))
	)
	var cfg: BoardConfig = view.config
	view._set_zoom(1.55)
	view._target = view._cell_ground_center(mid, cfg.cell_size)
	view._clamp_target()
	view._apply_camera()
	print(
		"pc60 capture: rider@%s -> %s path=%d intent=%s"
		% [rider.cell, dest, (preview.get("path", []) as Array).size(), preview.get("kind", "")]
	)

	await create_timer(0.9, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc60 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC60_WOLF_INTENT_PREVIEW_CAPTURE_OK %s" % abs_path)
	quit(0)
