extends SceneTree
## 一次性 GUI 证据采集（非 CI runner）。用法：godot --path . --script res://scripts/dev/game_loop_gui_capture.gd

const OUT_DIR := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/game-loop-feedback/"
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_title("Game loop GUI capture")
	var sandbox: Control = load("res://scenes/main/sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await create_timer(0.8).timeout
	_capture_viewport("01-sandbox-1280")
	sandbox._on_cell_clicked(Vector2i(1, 2))
	await create_timer(0.45).timeout
	_capture_viewport("02-move-attack-rings")
	for u in sandbox._board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "archer":
			u.cell = Vector2i(2, 2)
			break
	sandbox._board.changed.emit()
	sandbox._refresh_all()
	await create_timer(0.2).timeout
	sandbox._on_cell_clicked(Vector2i(2, 2))
	await create_timer(0.55).timeout
	_capture_viewport("03-damage-popup-hp")
	sandbox._show_turn_banner()
	await create_timer(0.35).timeout
	_capture_viewport("04-turn-banner")
	sandbox._on_end_turn_pressed()
	await create_timer(1.2).timeout
	_capture_viewport("05-opponent-turn")
	for u in sandbox._board.units:
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			u.hp = 0
	sandbox._board.changed.emit()
	sandbox._check_victory()
	await create_timer(0.4).timeout
	_capture_viewport("06-victory-overlay")
	DisplayServer.window_set_size(Vector2i(852, 393))
	await create_timer(0.5).timeout
	_capture_viewport("07-sandbox-852")
	print("GUI_CAPTURE_OK %s" % OUT_DIR)
	quit(0)


func _capture_viewport(name: String) -> void:
	await create_timer(0.15).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_warning("GUI capture: null image for %s" % name)
		return
	var path := OUT_DIR + name + ".png"
	img.save_png(path)
	print("saved ", path)
