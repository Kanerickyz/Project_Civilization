extends SceneTree
## 狼骑兵攻击距离 1（信息卡「射 1」）GUI 证据。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/wolf_range1_gui_capture.gd -- <out.png>

const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc-53-wolf-range1.png"
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))

	var sandbox: Control = (load("res://scenes/main/sandbox.tscn") as PackedScene).instantiate()
	root.add_child(sandbox)
	await create_timer(1.2, true, false, true).timeout

	if not sandbox.has_method("capture_show_unit_info"):
		push_error("wolf_range1_capture: missing capture_show_unit_info")
		quit(1)
		return
	if not sandbox.capture_show_unit_info("rider", false):
		push_error("wolf_range1_capture: failed to show rider info card")
		quit(1)
		return

	var board = sandbox.get("_board")
	var range_ok := false
	if board != null:
		for u in board.living_units():
			if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "rider":
				range_ok = u.def.attack_range == 1
				print(
					"wolf_range1_capture: rider move=%d atk_range=%d"
					% [u.def.move_range, u.def.attack_range]
				)
				break
	if not range_ok:
		push_error("wolf_range1_capture: rider attack_range is not 1")
		quit(1)
		return

	await create_timer(0.5, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("wolf_range1_capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("WOLF_RANGE1_CAPTURE_OK %s" % abs_path)
	quit(0)
