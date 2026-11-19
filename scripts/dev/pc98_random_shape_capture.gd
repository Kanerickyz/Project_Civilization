extends SceneTree
## PC-98 GUI：随机 10×8/8×10 + 随机边缘缩进预览（部署阶段棋盘视口）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc98_random_shape_capture.gd -- <out.png> [seed]
## 默认再写一份强制另一朝向的对比图到同目录 *-alt.png。

const DEFAULT_OUT := (
	"/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-98-random-shape-preview.png"
)
const BoardEdgeShapeScript := preload("res://scripts/map/board_edge_shape.gd")
const RosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	var seed_a := int(args[1]) if args.size() > 1 else 20261119
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-98 random shape")

	var path_a := await _capture_one(out_path, seed_a)
	if path_a.is_empty():
		quit(1)
		return

	# 找一个种子得到另一朝向，方便对比 10×8 vs 8×10。
	var seed_b := seed_a + 1
	var want_alt := _size_for_seed(seed_a)
	var guard := 0
	while guard < 64:
		guard += 1
		var sz := _size_for_seed(seed_b)
		if sz != want_alt:
			break
		seed_b += 1
	var alt_path := out_path.get_basename() + "-alt.png"
	var path_b := await _capture_one(alt_path, seed_b)
	if path_b.is_empty():
		quit(1)
		return

	print("PC98_RANDOM_CAPTURE_OK primary=%s alt=%s" % [path_a, path_b])
	quit(0)


func _size_for_seed(seed_value: int) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return BoardEdgeShapeScript.pick_battle_size(rng)


func _capture_one(out_path: String, seed_value: int) -> String:
	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC98 random capture: sandbox missing")
		return ""
	var sandbox: Control = packed.instantiate()
	# 在 _ready 前注入：替换 build 所用 seed——sandbox 无 seed API，改为手动重建。
	root.add_child(sandbox)
	await process_frame
	# 卸掉自动盘，按指定 seed 重建。
	var cfg: BoardConfig = sandbox._board_config
	var board: TacticalBoard = RosterScript.build_board_for_config(cfg, seed_value)
	sandbox._board = board
	if sandbox._board.changed.is_connected(sandbox._on_board_changed):
		pass
	else:
		board.changed.connect(sandbox._on_board_changed)
	sandbox._board_view.setup(cfg)
	sandbox._board_view.set_terrain_cells(board.terrain_cells())
	sandbox._enter_deployment_phase()
	sandbox._refresh_all()

	await process_frame
	await process_frame
	await create_timer(0.35).timeout

	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	var w := board.grid_width
	var h := board.grid_height
	if not (
		(w == 10 and h == 8) or (w == 8 and h == 10)
	):
		push_error("PC98 random capture: unexpected size %dx%d" % [w, h])
		sandbox.queue_free()
		await process_frame
		return ""

	var void_n := 0
	var present_n := 0
	for gx in range(w):
		for gy in range(h):
			var cell := Vector2i(gx, gy)
			if board.is_present(cell):
				present_n += 1
			else:
				void_n += 1
	if void_n < 4:
		push_error("PC98 random capture: expected some edge voids, got %d" % void_n)
		sandbox.queue_free()
		await process_frame
		return ""

	var players := 0
	var opponents := 0
	for u in board.living_units():
		if not board.is_present(u.cell):
			push_error("PC98 random capture: unit on void %s" % str(u.cell))
			sandbox.queue_free()
			await process_frame
			return ""
		if u.faction == TacticalFaction.Id.PLAYER:
			players += 1
		elif u.faction == TacticalFaction.Id.OPPONENT:
			opponents += 1
	if players != 6 or opponents != 6:
		push_error(
			"PC98 random capture: expected 6+6, got %d+%d" % [players, opponents]
		)
		sandbox.queue_free()
		await process_frame
		return ""

	sandbox._board_view._set_zoom(sandbox._board_view._effective_zoom_min() * 1.05)
	sandbox._board_view.recenter_camera()
	sandbox._refresh_all()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout

	var img: Image = sandbox._board_view._viewport.get_texture().get_image()
	if img == null:
		push_error("PC98 random capture: null board image")
		sandbox.queue_free()
		await process_frame
		return ""
	var err := img.save_png(out_path)
	if err != OK:
		push_error("PC98 random capture: save failed %s" % out_path)
		sandbox.queue_free()
		await process_frame
		return ""
	print(
		"saved %dx%d voids=%d present=%d seed=%d %s"
		% [w, h, void_n, present_n, seed_value, out_path]
	)
	sandbox.queue_free()
	await process_frame
	return out_path
