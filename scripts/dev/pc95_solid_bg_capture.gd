extends SceneTree
## PC-95 GUI：沙盘棋盘区纯色底（#121820），无右下橄榄绿块。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc95_solid_bg_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-95-solid-bg.png"
const SOLID_BG := Color("121820")
const OLIVE_BUG := Color("56603a")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-95 solid sandbox bg")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC95 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	await create_timer(0.35).timeout

	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	var look: BoardLook = sandbox._board_config.look
	if look == null or not look.background_color.is_equal_approx(SOLID_BG):
		push_error(
			"PC95 capture: BoardLook.background_color want %s got %s"
			% [SOLID_BG, look.background_color if look else null]
		)
		quit(1)
		return
	if sandbox._board_view._chrome == null or not sandbox._board_view._chrome.color.is_equal_approx(SOLID_BG):
		push_error("PC95 capture: chrome should be solid #121820")
		quit(1)
		return
	if sandbox._board_view._backdrop == null or not sandbox._board_view._backdrop.color.is_equal_approx(
		SOLID_BG
	):
		push_error("PC95 capture: backdrop should be solid #121820")
		quit(1)
		return
	if sandbox._board_view._chrome.color.is_equal_approx(OLIVE_BUG):
		push_error("PC95 capture: olive green bug color still in use")
		quit(1)
		return

	sandbox._board_view._set_zoom(1.05)
	sandbox._board_view.recenter_camera()
	sandbox._refresh_all()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("PC95 capture: null window image")
		quit(1)
		return
	img.save_png(out_path)
	print("PC95_CAPTURE_OK bg=%s %s" % [SOLID_BG, out_path])
	quit(0)
