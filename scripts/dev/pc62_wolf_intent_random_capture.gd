extends SceneTree
## 狼骑兵开战初相独立随机 GUI 证据。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc62_wolf_intent_random_capture.gd -- <out.png>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc-62-wolf-intent-random.png"
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

	# 多试几次布阵，确保画面上可见至少两种初相（功能本身已是独立随机）。
	var board: TacticalBoard = null
	var kinds: Dictionary = {}
	var intent_counts: Dictionary = {}
	for attempt in range(32):
		board = TacticalSandboxRoster.build_board_for_config(cfg, 20261119 + attempt)
		kinds.clear()
		intent_counts.clear()
		for u in board.living_units():
			if not TacticalEnemyAi.uses_behavior_sm(u):
				continue
			kinds[u.next_intent] = true
			var key := int(u.next_intent)
			intent_counts[key] = int(intent_counts.get(key, 0)) + 1
		if kinds.size() >= 2:
			break
	if board == null or kinds.size() < 2:
		push_error("pc62 capture: failed to get mixed initial intents")
		quit(1)
		return

	view.set_terrain_cells(board.terrain_cells())
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	view._set_zoom(1.35)
	view.recenter_camera()

	print(
		"pc62 capture: riders intents=%s kinds=%d"
		% [str(intent_counts), kinds.size()]
	)

	await create_timer(0.9, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc62 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC62_WOLF_INTENT_RANDOM_CAPTURE_OK %s" % abs_path)
	quit(0)
