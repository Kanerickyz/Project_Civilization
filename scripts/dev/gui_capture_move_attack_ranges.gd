extends SceneTree
## 选中四名玩家单位并截图移动/攻击 overlay。用法见 tools/capture_move_attack_ranges.sh


const UNIT_IDS: Array[String] = ["knight", "archer", "mini_pekka", "wardrum"]

var _scene: Node
var _out_dir := "user://move_attack_ranges"
var _index := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = String(args[0])
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("gui_capture_ranges: sandbox missing")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	var timer := create_timer(0.55, true, false, true)
	timer.timeout.connect(_capture_next)


func _capture_next() -> void:
	if not _scene.has_method("capture_select_player_unit"):
		push_error("gui_capture_ranges: sandbox missing capture_select_player_unit")
		quit(1)
		return
	if _index >= UNIT_IDS.size():
		print("GUI_CAPTURE_RANGES_OK")
		quit(0)
		return
	var unit_id: String = UNIT_IDS[_index]
	_scene.capture_select_player_unit(unit_id)
	var pending_id := _index
	_index += 1
	var timer := create_timer(0.35, true, false, true)
	timer.timeout.connect(_save_shot.bind(unit_id, pending_id))


func _save_shot(unit_id: String, _pending: int) -> void:
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := abs_dir.path_join("%s_selected.png" % unit_id)
	var err := img.save_png(path)
	if err != OK:
		push_error("gui_capture_ranges: save failed %s" % path)
		quit(1)
		return
	print("GUI_CAPTURE_RANGE ", path)
	_capture_next()
