extends SceneTree
## 草地/直城墙 GUI 证据：沙盘选中单位看城墙挡路。
## 用法：godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 \
##   --script res://scripts/dev/grass_wall_tiles_gui_capture.gd -- sandbox <out.png> [w] [h] [zoom]

const EDITOR_WALLS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
	Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6),
	Vector2i(2, 5),
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := String(args[0]) if args.size() > 0 else "sandbox"
	var out_path := String(args[1]) if args.size() > 1 else "user://grass_wall_capture.png"
	var w := int(args[2]) if args.size() > 2 else 1280
	var h := int(args[3]) if args.size() > 3 else 720
	var zoom := float(args[4]) if args.size() > 4 else 1.0
	DisplayServer.window_set_size(Vector2i(w, h))
	if mode == "editor":
		push_warning("grass_wall_capture: map editor removed; using sandbox")
		mode = "sandbox"
	var scene_path := "res://scenes/main/sandbox.tscn"
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(0.3, true, false, true).timeout
	# 摆拍：铺墙并选中单位看挡路。
	var drummer: TacticalUnitInstance = scene._board.unit_at(Vector2i(2, 4))
	if drummer == null:
		for u in scene._board.living_units():
			if u.faction == TacticalFaction.Id.PLAYER:
				drummer = u
				break
	scene._board.set_terrain_cells({
		Vector2i(5, 3): &"wall_straight",
		Vector2i(5, 4): &"wall_straight",
		Vector2i(5, 5): &"wall_straight",
		Vector2i(5, 6): &"wall_straight",
	})
	scene._board_view.set_terrain_cells(scene._board.terrain_cells())
	if drummer != null:
		drummer.cell = Vector2i(4, 5)
		scene._on_cell_clicked(drummer.cell)
		await create_timer(1.8, true, false, true).timeout
		scene._on_cell_clicked(Vector2i(5, 5))
	var view := _find_view(scene)
	if view != null and absf(zoom - 1.0) > 0.01:
		view._set_zoom(zoom)
	await create_timer(0.6, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("grass_wall_capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("GRASS_WALL_CAPTURE_OK %s" % abs_path)
	quit(0)


func _find_view(scene: Node) -> Node:
	if scene.has_node("%GridBoardView"):
		return scene.get_node("%GridBoardView")
	return scene.find_child("GridBoardView", true, false)
