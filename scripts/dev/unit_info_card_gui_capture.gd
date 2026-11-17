extends SceneTree
## 一次性 GUI：长按信息卡证据。用法见 tools 或直接 --script。


const OUT_PATH := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc27-unit-info-card.png"


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
	if sandbox.has_method("capture_show_unit_info"):
		sandbox.capture_show_unit_info("archer", true)
	await create_timer(0.45).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	if err != OK:
		push_error("unit_info_card_capture: save failed %s" % out)
		quit(1)
		return
	print("GUI_CAPTURE_OK ", out)
	quit(0)
