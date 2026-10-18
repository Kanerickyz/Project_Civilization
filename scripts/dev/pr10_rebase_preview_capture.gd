extends SceneTree

const OUT_DIR := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pr10-rebase-preview/"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _capture_at_size(Vector2i(1280, 720), "1280")
	await _capture_at_size(Vector2i(852, 393), "852")
	print("PR10_REBASE_PREVIEW_OK %s" % OUT_DIR)
	quit(0)


func _capture_at_size(win: Vector2i, tag: String) -> void:
	DisplayServer.window_set_size(win)
	var sandbox: Control = load("res://scenes/main/sandbox.tscn").instantiate()
	for c in root.get_children():
		c.queue_free()
	root.add_child(sandbox)
	await create_timer(0.85).timeout
	_shot(sandbox, "%s-01-sandbox" % tag)
	sandbox.capture_select_player_unit("archer")
	await create_timer(0.45).timeout
	_shot(sandbox, "%s-02-range-rings-archer" % tag)
	for u in sandbox._board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "archer":
			u.cell = Vector2i(4, 4)
			break
	sandbox._board.changed.emit()
	sandbox._refresh_all()
	sandbox.capture_select_player_unit("knight")
	await create_timer(0.25).timeout
	var knight: TacticalUnitInstance = null
	for u in sandbox._board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "knight":
			knight = u
			break
	if knight != null:
		sandbox._on_cell_clicked(knight.cell + Vector2i(1, 0))
	await create_timer(0.55).timeout
	_shot(sandbox, "%s-03-damage-popup" % tag)
	sandbox._show_turn_banner()
	await create_timer(0.35).timeout
	_shot(sandbox, "%s-04-turn-banner" % tag)


func _shot(_sandbox: Control, name: String) -> void:
	await create_timer(0.1).timeout
	var img := root.get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	img.save_png(path)
	print("saved ", path)
