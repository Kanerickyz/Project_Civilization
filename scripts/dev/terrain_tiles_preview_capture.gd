extends SceneTree
## 地块近景截图：独立 GridBoardView，摆横/竖/拐角城墙与高亮 overlay。
## 用法：godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 \
##   --script res://scripts/dev/terrain_tiles_preview_capture.gd -- <out.png> [w] [h] [zoom] [with_units]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://terrain_tiles_preview.png"
	var w := int(args[1]) if args.size() > 1 else 1280
	var h := int(args[2]) if args.size() > 2 else 720
	var zoom := float(args[3]) if args.size() > 3 else 1.6
	var with_units := args.size() > 4 and String(args[4]) == "1"
	DisplayServer.window_set_size(Vector2i(w, h))

	var cfg := (load("res://resources/map/board_config.tres") as BoardConfig).duplicate() as BoardConfig
	var host := Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view := GridBoardView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(view)
	view.setup(cfg)

	var walls := {}
	for x in range(1, 5):
		walls[Vector2i(x, 2)] = &"wall_straight"
	for y in range(3, 7):
		walls[Vector2i(6, y)] = &"wall_straight"
	walls[Vector2i(3, 5)] = &"wall_straight"
	view.set_terrain_cells(walls)

	var units: Array = []
	if with_units:
		var def := load("res://resources/units/knight.tres") as TacticalUnitDef
		if def != null:
			units.append(TacticalUnitInstance.new(def, 0, Vector2i(4, 4)))
	view.sync_tactical_units(units, Vector2i(4, 4), [Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 5)], [Vector2i(5, 5)])
	view._set_zoom(zoom)

	await create_timer(0.6, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("terrain_preview: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("TERRAIN_PREVIEW_OK ", abs_path)
	quit(0)
