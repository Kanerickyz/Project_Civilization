extends SceneTree
## PC-57 GUI：血攻「攻」+ 燃烧角标（无 ◆）字体证据。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc57_unit_label_font_capture.gd

const OUT_PATH := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-57-unit-label-font.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-57 unit label font")

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

	var board := TacticalSandboxRoster.build_board_for_config(cfg, 20261117)
	TacticalSandboxRoster.spawn_pending_enemies(board, 20261117)
	view.set_terrain_cells(board.terrain_cells())
	# 给一只狼骑兵叠燃烧，露出「燃N」角标；血攻读数全场常驻。
	var burned := 0
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and burned == 0:
			u.cell = Vector2i(3, 2)
			u.add_burn_stacks(2)
			burned = 1
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	view._set_zoom(1.35)
	view.recenter_camera()

	await create_timer(0.9, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("pc57_capture: save_png failed %s err=%s" % [OUT_PATH, err])
		quit(1)
		return
	print("PC57_CAPTURE_OK burned=%d %s" % [burned, OUT_PATH])
	quit(0)
