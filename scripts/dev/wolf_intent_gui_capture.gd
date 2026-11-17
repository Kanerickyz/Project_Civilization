extends SceneTree
## 狼骑兵意图角标 GUI 证据。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/wolf_intent_gui_capture.gd -- <out.png>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc-52-wolf-intent.png"
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
	view.set_terrain_cells(board.terrain_cells())
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	view._set_zoom(1.35)
	view.recenter_camera()

	var riders := 0
	var attack_intents := 0
	for u in board.living_units():
		if TacticalEnemyAi.uses_behavior_sm(u):
			riders += 1
			if u.next_intent == TacticalEnemyAi.Intent.ATTACK:
				attack_intents += 1
	print("wolf_intent_capture: riders=%d attack_intents=%d" % [riders, attack_intents])

	await create_timer(0.9, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("wolf_intent_capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("WOLF_INTENT_CAPTURE_OK %s" % abs_path)
	quit(0)
