extends SceneTree
## 一次性 GUI 截图：加载沙盘并保存根视口 PNG。用法见 tools/capture_sandbox_gui.sh


var _out_path := "user://sandbox_capture.png"
var _zoom := 1.0


func _initialize() -> void:
	_out_path = "user://sandbox_capture.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = String(args[0])
	var w := 1280
	var h := 720
	if args.size() >= 3:
		w = int(args[1])
		h = int(args[2])
	if args.size() >= 4:
		_zoom = float(args[3])
	DisplayServer.window_set_size(Vector2i(w, h))
	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("gui_capture: sandbox scene missing")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	scene.set_meta("capture_zoom", _zoom)
	root.add_child(scene)
	var timer := create_timer(0.65, true, false, true)
	timer.timeout.connect(_save_and_quit.bind(scene))


func _apply_board_zoom(scene: Node, zoom: float) -> void:
	var view := _find_grid_board_view(scene)
	if view == null:
		return
	view._set_zoom(zoom)


func _find_grid_board_view(node: Node) -> GridBoardView:
	if node is GridBoardView:
		return node as GridBoardView
	for child in node.get_children():
		var found := _find_grid_board_view(child)
		if found != null:
			return found
	return null


func _save_and_quit(scene: Node) -> void:
	var zoom := float(scene.get_meta("capture_zoom", 1.0))
	if absf(zoom - 1.0) > 0.01:
		_apply_board_zoom(scene, zoom)
		await create_timer(0.12, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs := ProjectSettings.globalize_path(_out_path)
	var err := img.save_png(abs)
	if err != OK:
		push_error("gui_capture: save_png failed %s err=%s" % [abs, err])
		quit(1)
		return
	print("GUI_CAPTURE_OK ", abs)
	quit(0)
