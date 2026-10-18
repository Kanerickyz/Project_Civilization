extends SceneTree

const OUT_DIR := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/unit-scale-regression/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var sandbox: Control = load("res://scenes/main/sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await create_timer(0.9).timeout
	_capture("pr10-fixed-sandbox-1280")
	sandbox._on_cell_clicked(Vector2i(1, 2))
	await create_timer(0.4).timeout
	_capture("pr10-fixed-knight-selected")
	print("UNIT_SCALE_CAPTURE_OK ortho=%s unit_h=%s" % [
		sandbox._board_config.camera_ortho_size,
		sandbox._board_config.unit_world_height,
	])
	quit(0)


func _capture(name: String) -> void:
	await create_timer(0.12).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + name + ".png")
	print("saved ", OUT_DIR + name + ".png")
