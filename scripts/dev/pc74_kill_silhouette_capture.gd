extends SceneTree
## PC-74 GUI：击杀红横带 + 被击杀敌方（狼骑）黑剪影。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc74_kill_silhouette_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-74-kill-silhouette.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-74 kill silhouette")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC74 capture: sandbox missing")
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
		push_error("PC74 capture: rider texture_red missing")
		quit(1)
		return
	var wolf_tex: Texture2D = rider_def.texture_red

	if not sandbox.has_method("capture_play_kill_impact"):
		push_error("PC74 capture: capture_play_kill_impact missing")
		quit(1)
		return
	if not sandbox.capture_play_kill_impact(wolf_tex):
		push_error("PC74 capture: kill impact not visible")
		quit(1)
		return

	# 截在 hold 峰值（pop 后、fade 前）。
	await create_timer(0.08).timeout
	await process_frame
	await process_frame

	var fx: Control = sandbox._kill_impact as Control
	if fx == null or not fx.visible or fx.modulate.a < 0.5:
		push_error("PC74 capture: expected kill impact flashing")
		quit(1)
		return
	var sil: Texture2D = fx._silhouette_tex as Texture2D
	if sil == null:
		push_error("PC74 capture: expected unit silhouette texture")
		quit(1)
		return

	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("PC74 capture: null window image")
		quit(1)
		return
	var err := img.save_png(out_path)
	if err != OK:
		push_error("PC74 capture: save_png failed %s err=%s" % [out_path, err])
		quit(1)
		return
	print(
		"PC74_CAPTURE_OK visible=%s alpha=%.2f tex=%s %s"
		% [fx.visible, fx.modulate.a, sil.resource_path, out_path]
	)
	quit(0)
