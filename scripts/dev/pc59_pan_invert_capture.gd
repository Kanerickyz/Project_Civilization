extends SceneTree
## PC-59 GUI：竖向往下滑动后视角下移（+forward）证据。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc59_pan_invert_capture.gd

const OUT_PATH := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-59-pan-invert.png"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-59 pan invert Y")

	var cfg := (load("res://resources/map/board_config.tres") as BoardConfig).duplicate() as BoardConfig
	var host := Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("121820")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var view := GridBoardView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(view)
	view.setup(cfg)

	var board := TacticalSandboxRoster.build_board_for_config(cfg, 20261118)
	view.set_terrain_cells(board.terrain_cells())
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	view._set_zoom(1.2)
	view.recenter_camera()
	await process_frame
	await process_frame
	view._apply_camera()

	# 模拟屏幕往下滑动约 180px：视角应沿 +forward。
	var before: Vector3 = view._target
	var pan := view.compute_pan_world_delta(Vector2(0.0, 180.0))
	view._target = before + pan
	view._clamp_target()
	view._apply_camera()
	var yaw := deg_to_rad(cfg.camera_yaw_deg)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var along := pan.dot(forward)
	if along <= 0.0:
		push_error("pc59_capture: downward screen delta should move +forward (got %s)" % along)
		quit(1)
		return

	await create_timer(0.5, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("pc59_capture: save_png failed %s err=%s" % [OUT_PATH, err])
		quit(1)
		return
	print("PC59_CAPTURE_OK along_forward=%.3f %s" % [along, OUT_PATH])
	quit(0)
