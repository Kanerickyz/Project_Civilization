extends SceneTree
## 湖/林 GUI 证据：固定 seed 成簇布局 + GridBoardView 截图。
## 用法：godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/lake_forest_gui_capture.gd -- <out.png> [seed]

const DEFAULT_SEED := 20261117


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc48-lake-forest.png"
	var seed_value := int(args[1]) if args.size() > 1 else DEFAULT_SEED
	DisplayServer.window_set_size(Vector2i(786, 1704))

	var cfg := (load("res://resources/map/board_config.tres") as BoardConfig).duplicate() as BoardConfig
	var gen: Dictionary = ClusterTerrainGenerator.generate(cfg.grid_width, cfg.grid_height, seed_value)
	var map: MapData = gen["map"] as MapData
	print(
		"lake_forest_capture: seed=%d lake=%d forest=%d ratio=%.3f/%.3f"
		% [seed_value, int(gen["lake_count"]), int(gen["forest_count"]), float(gen["lake_ratio"]), float(gen["forest_ratio"])]
	)

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
	view.set_terrain_cells(map.terrain_dictionary())

	var board := TacticalSandboxRoster.build_board_for_config(cfg, seed_value)
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	view._set_zoom(1.15)
	view.recenter_camera()

	await create_timer(0.8, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("lake_forest_capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("LAKE_FOREST_CAPTURE_OK %s" % abs_path)
	quit(0)
