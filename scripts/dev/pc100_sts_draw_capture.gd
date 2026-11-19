extends SceneTree
## PC-100 GUI：回合开始 STS 逐张抽牌动画中途截图。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc100_sts_draw_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-100-sts-draw.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-100 STS draw")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC100 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	# 等 3～4 张飞入后再截，底栏更易辨认。
	await create_timer(0.95).timeout

	if sandbox.get("_turn_banner_panel") != null:
		sandbox.get("_turn_banner_panel").visible = false

	var hand_fan = sandbox.get("_hand_fan")
	var n := 0
	if hand_fan != null and hand_fan.get("_cards") != null:
		n = (hand_fan.get("_cards") as Array).size()
	var drawing := false
	if hand_fan != null:
		drawing = bool(hand_fan.get("_drawing"))
	print("PC100_STATE hand_cards=%d drawing=%s" % [n, drawing])
	if n < 1:
		push_error("PC100 capture: expected cards mid-draw")
		quit(1)
		return

	await process_frame
	var vp := root.get_viewport()
	var img: Image = vp.get_texture().get_image()
	if img == null:
		img = DisplayServer.screen_get_image(0)
	if img == null:
		push_error("PC100 capture: no image")
		quit(1)
		return
	var err := img.save_png(out_path)
	if err != OK:
		push_error("PC100 capture: save failed %d" % err)
		quit(1)
		return
	print("PC100_CAPTURE_OK %s" % out_path)
	quit(0)
