extends SceneTree

const OUT_DIR := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/banner-rings-fix/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _run(Vector2i(1280, 720), "1280")
	await _run(Vector2i(852, 393), "852")
	print("BANNER_RINGS_FIX_OK %s" % OUT_DIR)
	quit(0)


func _run(win: Vector2i, tag: String) -> void:
	DisplayServer.window_set_size(win)
	for c in root.get_children():
		c.queue_free()
	var sandbox: Control = load("res://scenes/main/sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await create_timer(0.85).timeout
	sandbox._show_turn_banner()
	await create_timer(0.25).timeout
	_shot("%s-turn-banner-bar" % tag)
	sandbox.capture_select_player_unit("archer")
	await create_timer(0.65).timeout
	await _shot("%s-range-rings-selected" % tag)


func _shot(name: String) -> void:
	await create_timer(0.12).timeout
	root.get_viewport().get_texture().get_image().save_png(OUT_DIR + name + ".png")
	print("saved ", OUT_DIR + name + ".png")
