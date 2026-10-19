extends SceneTree
## 草地 Billboard 装饰 GUI 截图：对战沙盘默认布局。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 \
##   --script res://scripts/dev/grass_billboard_props_gui_capture.gd -- <out.png> [w] [h]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://grass_billboard_sandbox.png"
	var w := int(args[1]) if args.size() > 1 else 1280
	var h := int(args[2]) if args.size() > 2 else 720
	DisplayServer.window_set_size(Vector2i(w, h))
	var scene: Node = (load("res://scenes/main/sandbox.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(1.2, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	if img.save_png(abs_path) != OK:
		push_error("grass_billboard_capture: save_png failed %s" % abs_path)
		quit(1)
		return
	print("GRASS_BILLBOARD_CAPTURE_OK ", abs_path)
	quit(0)
