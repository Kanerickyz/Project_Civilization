extends SceneTree
## PC-71 GUI：非通用技拖牌高亮可释放格 + STS 曲线箭头。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc71_skill_free_play_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-71-skill-free-play.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-71 skill free play")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC71 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	await create_timer(0.2).timeout

	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await process_frame
	await create_timer(0.35).timeout

	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	var deck: TacticalCardDeck = sandbox._deck
	# 保证手牌有燃爆，便于攻击射程高亮+箭头。
	var burn: TacticalActionCard = null
	for c in deck.hand:
		if c.kind == TacticalActionCard.Kind.SKILL_BURN_ATTACK:
			burn = c
			break
	if burn == null:
		for c in deck.draw_pile:
			if c.kind == TacticalActionCard.Kind.SKILL_BURN_ATTACK:
				burn = c
				break
		if burn != null:
			deck.draw_pile.erase(burn)
			deck.hand.append(burn)
	if burn == null:
		burn = TacticalActionCard.make_skill_burn_attack("boomling", 3)
		deck.hand.append(burn)
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	await process_frame

	if not sandbox.capture_skill_drag_preview("skill_burn_attack"):
		push_error("PC71 capture: skill drag preview failed")
		quit(1)
		return

	# 断言：可释放格与箭头已挂上。
	var release_n: int = sandbox._board_view._overlay_skill_release.size()
	if release_n <= 0:
		push_error("PC71 capture: expected skill release overlay cells")
		quit(1)
		return
	if sandbox._board_view._skill_aim_arrow == null:
		push_error("PC71 capture: expected STS curve arrow node")
		quit(1)
		return

	sandbox._board_view._set_zoom(1.15)
	sandbox._board_view.recenter_camera()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC71 capture: null board image")
		quit(1)
		return
	svp.save_png(out_path)
	print(
		"PC71_CAPTURE_OK release_cells=%d arrow=%s %s"
		% [release_n, sandbox._board_view._skill_aim_arrow != null, out_path]
	)
	quit(0)
