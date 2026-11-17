extends SceneTree
## 一次性 GUI：拖牌悬停格高亮 + 单位选中脉冲证据。


const OUT_PATH := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc30-card-drag-highlight.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := OUT_PATH
	if args.size() > 0:
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var sandbox: Control = load("res://scenes/main/sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await create_timer(1.2).timeout
	if sandbox.has_method("capture_card_drag_hover"):
		sandbox.capture_card_drag_hover("archer", true)
	await create_timer(0.55).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	if err != OK:
		push_error("card_drag_hover_capture: save failed %s" % out)
		quit(1)
		return
	print("GUI_CAPTURE_OK ", out)
	quit(0)
