extends SceneTree
## 敌方狼骑兵点选行动格 GUI 证据（绿移/红攻）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/wolf_action_tiles_gui_capture.gd -- <out.png>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc-55-wolf-tiles.png"
	DisplayServer.window_set_size(Vector2i(786, 1704))

	var cfg := (load("res://resources/map/board_config.tres") as BoardConfig).duplicate() as BoardConfig
	var host := Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("121820")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var view := GridBoardView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(view)
	view.setup(cfg)

	var board := TacticalSandboxRoster.build_board_for_config(cfg, 20261117)
	TacticalSandboxRoster.spawn_pending_enemies(board, 20261117)
	view.set_terrain_cells(board.terrain_cells())

	var rider: TacticalUnitInstance = null
	for u in board.living_units():
		if TacticalEnemyAi.uses_behavior_sm(u):
			rider = u
			break
	if rider == null:
		push_error("wolf_action_tiles_capture: no rider")
		quit(1)
		return

	rider.remaining_move_budget = 0
	var move_cells := board.preview_reachable_move_cells(rider, TacticalEnemyAi.MOVE_STEP_CAP)
	var attack_cells := board.attack_range_cells(rider)
	if move_cells.is_empty() or attack_cells.is_empty():
		push_error(
			"wolf_action_tiles_capture: empty overlay move=%d attack=%d"
			% [move_cells.size(), attack_cells.size()]
		)
		quit(1)
		return

	view.sync_tactical_units(
		board.living_units(),
		rider.cell,
		move_cells,
		attack_cells
	)
	# 镜头对准选中狼骑，放大便于看清绿移/红攻邻域。
	view._set_zoom(1.7)
	view._target = view._cell_ground_center(rider.cell, cfg.cell_size)
	view._clamp_target()
	view._apply_camera()
	print(
		"wolf_action_tiles_capture: rider@%s moves=%d attacks=%d"
		% [rider.cell, move_cells.size(), attack_cells.size()]
	)

	await create_timer(0.9, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("wolf_action_tiles_capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("WOLF_ACTION_TILES_CAPTURE_OK %s" % abs_path)
	quit(0)
