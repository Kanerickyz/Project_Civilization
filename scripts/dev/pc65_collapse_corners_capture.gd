extends SceneTree
## PC-65 GUI：四角向内缩圈（非整边）。用法：
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc65_collapse_corners_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-65-collapse-corners.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-65 collapse corners")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC65 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(1.2).timeout
	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	# 快进到第 7 回合（stage=3）：四角楔块清晰可见，边心仍安全。
	sandbox._clock.turn = 7
	sandbox._clock.player_active = true
	var newly: Array = sandbox._board.sync_map_collapse(7)
	if sandbox._board.collapse_stage != 3:
		push_error(
			"PC65 capture: expected stage3, got stage=%d newly=%d"
			% [sandbox._board.collapse_stage, newly.size()]
		)
		quit(1)
		return
	var bw: int = sandbox._board.grid_width
	var bh: int = sandbox._board.grid_height
	var danger_n: int = sandbox._board.danger_cells_for_view().size()
	# stage3 = corner_distance 0..2；边心中段须仍安全（非整边外环）。
	var expected := 0
	for gx in range(bw):
		for gy in range(bh):
			if sandbox._board.corner_distance(Vector2i(gx, gy)) <= 2:
				expected += 1
	if danger_n != expected:
		push_error("PC65 capture: expected %d corner-wedge cells, got %d" % [expected, danger_n])
		quit(1)
		return
	var mid_edge := Vector2i(bw / 2, 0)
	if sandbox._board.corner_distance(mid_edge) <= 2:
		mid_edge = Vector2i((bw - 1) / 2, 0)
	if sandbox._board.is_danger_cell(mid_edge):
		push_error("PC65 capture: mid-edge %s must stay safe at stage3" % str(mid_edge))
		quit(1)
		return
	var corners: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(bw - 1, 0),
		Vector2i(0, bh - 1),
		Vector2i(bw - 1, bh - 1),
	]
	for corner in corners:
		if not sandbox._board.is_danger_cell(corner):
			push_error("PC65 capture: corner %s must be danger" % str(corner))
			quit(1)
			return

	var player: TacticalUnitInstance = null
	for u in sandbox._board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			player = u
			break
	if player != null:
		player.cell = Vector2i(0, 0)
		player.hp = maxi(player.hp, 8)
	sandbox._board.changed.emit()
	sandbox._refresh_all()
	await create_timer(0.2).timeout

	var danger_events: Array = sandbox._board.process_danger_ticks(TacticalFactionScript.Id.PLAYER)
	for ev in danger_events:
		var cell: Vector2i = ev.get("cell", Vector2i.ZERO)
		var dmg := int(ev.get("damage", 0))
		var unit := ev.get("unit") as TacticalUnitInstance
		if unit != null and dmg > 0:
			sandbox._board_view.play_damage_popup(cell, dmg)
			sandbox._board_view.play_unit_hit(unit)
	sandbox._last_log = "四角崩塌 · 第 %d 层危险区（伤 %d）" % [
		sandbox._board.collapse_stage,
		sandbox._board.collapse_danger_damage(),
	]
	sandbox._refresh_all()
	await create_timer(0.18).timeout
	await process_frame
	await process_frame

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC65 capture: null board image")
		quit(1)
		return
	svp.save_png(out_path)
	print(
		"PC65_CAPTURE_OK stage=%d danger=%d newly=%d danger_events=%d dmg=%d %s"
		% [
			sandbox._board.collapse_stage,
			danger_n,
			newly.size(),
			danger_events.size(),
			sandbox._board.collapse_danger_damage(),
			out_path,
		]
	)
	quit(0)
