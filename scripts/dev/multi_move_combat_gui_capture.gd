extends SceneTree
## GUI 证据：移力池、Tween 战斗、敌方逐单位行动。用法见 tools/capture_multi_move_combat_gui.sh

const OUT_DIR := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/multi-move-combat/"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_title("Multi-move combat GUI capture")
	var sandbox: Control = load("res://scenes/main/sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await create_timer(0.85).timeout
	_capture_viewport("01-sandbox-1280")
	DisplayServer.window_set_size(Vector2i(852, 393))
	await create_timer(0.75).timeout
	_capture_viewport("07-sandbox-852")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(0.65).timeout
	sandbox.capture_select_player_unit("archer")
	await create_timer(0.45).timeout
	_capture_viewport("02-archer-move-budget-rings")
	sandbox._on_cell_clicked(Vector2i(2, 2))
	await create_timer(0.35).timeout
	_capture_viewport("03-archer-first-move")
	sandbox._on_cell_clicked(Vector2i(3, 2))
	await create_timer(0.35).timeout
	_capture_viewport("04-archer-second-move-budget")
	for u in sandbox._board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "knight":
			u.cell = Vector2i(4, 2)
			break
	sandbox._board.changed.emit()
	sandbox._refresh_all()
	await create_timer(0.25).timeout
	sandbox._on_cell_clicked(Vector2i(4, 2))
	await create_timer(0.65).timeout
	_capture_viewport("05-attack-tween-popup")
	sandbox._on_end_turn_pressed()
	for _i in 40:
		if not sandbox._input_locked:
			break
		await create_timer(0.15).timeout
	await create_timer(0.35).timeout
	_capture_viewport("06-opponent-sequential-turn")
	print("GUI_CAPTURE_OK %s" % OUT_DIR)
	quit(0)


func _capture_viewport(name: String) -> void:
	await create_timer(0.12).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_warning("GUI capture: null image for %s" % name)
		return
	var path := OUT_DIR + name + ".png"
	img.save_png(path)
	print("saved ", path)
