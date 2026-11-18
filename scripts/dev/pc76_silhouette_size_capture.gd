extends SceneTree
## PC-76 GUI：击杀剪影尺寸对齐棋盘单位 + 最近邻减锯齿。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc76_silhouette_size_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-76-silhouette-size.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-76 silhouette size")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC76 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await process_frame
	await create_timer(0.4).timeout

	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	var rider_def: TacticalUnitDef = load("res://resources/units/rider.tres") as TacticalUnitDef
	if rider_def == null or rider_def.texture_red == null:
		push_error("PC76 capture: rider texture_red missing")
		quit(1)
		return
	var wolf_tex: Texture2D = rider_def.texture_red
	var vis := rider_def.visual_scale if rider_def.visual_scale > 0.0 else 1.0
	var expected: Vector2 = sandbox._board_view.unit_texture_screen_size(wolf_tex, vis)
	if expected.x < 8.0 or expected.y < 8.0:
		push_error("PC76 capture: expected board unit screen size too small %s" % expected)
		quit(1)
		return

	if not sandbox.has_method("capture_play_kill_impact"):
		push_error("PC76 capture: capture_play_kill_impact missing")
		quit(1)
		return
	if not sandbox.capture_play_kill_impact(wolf_tex):
		push_error("PC76 capture: kill impact not visible")
		quit(1)
		return

	# 截在 hold 峰值（pop 后、fade 前）。
	await create_timer(0.08).timeout
	await process_frame
	await process_frame

	var fx: Control = sandbox._kill_impact as Control
	if fx == null or not fx.visible or fx.modulate.a < 0.5:
		push_error("PC76 capture: expected kill impact flashing")
		quit(1)
		return
	if fx.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		push_error("PC76 capture: expected TEXTURE_FILTER_NEAREST")
		quit(1)
		return
	var sil: Texture2D = fx._silhouette_tex as Texture2D
	if sil == null:
		push_error("PC76 capture: expected unit silhouette texture")
		quit(1)
		return
	var got: Vector2 = fx._silhouette_screen_size as Vector2
	if absf(got.x - expected.x) > 1.5 or absf(got.y - expected.y) > 1.5:
		push_error(
			"PC76 capture: silhouette screen size %s != board unit %s" % [got, expected]
		)
		quit(1)
		return
	# 不得再按横带 92% 放大（旧行为约 0.92 * band_h）。
	# 与 kill_impact_fx.BAND_HEIGHT_RATIO 保持同值。
	var band_h := fx.size.y * 0.34
	if got.y > band_h * 0.55:
		push_error(
			"PC76 capture: silhouette still too tall vs band: got.y=%.1f band_h=%.1f"
			% [got.y, band_h]
		)
		quit(1)
		return

	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("PC76 capture: null window image")
		quit(1)
		return
	var err := img.save_png(out_path)
	if err != OK:
		push_error("PC76 capture: save_png failed %s err=%s" % [out_path, err])
		quit(1)
		return
	print(
		"PC76_CAPTURE_OK visible=%s alpha=%.2f size=%s expected=%s filter=nearest %s"
		% [fx.visible, fx.modulate.a, got, expected, out_path]
	)
	quit(0)
