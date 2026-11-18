extends SceneTree
## PC-79 GUI：空手自动结束须进入对手段（第 1 回合 · 对手行动），不得跳到下一玩家段。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc79_auto_end_turn_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-79-auto-end-turn.png"
const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-79 auto end turn")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC79 capture: sandbox missing")
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
	await create_timer(0.4).timeout

	if sandbox.get("_turn_banner_panel") != null:
		sandbox.get("_turn_banner_panel").modulate.a = 0.0

	var deck = sandbox.get("_deck")
	if deck == null or deck.hand.is_empty():
		push_error("PC79 capture: expected non-empty hand after battle start")
		quit(1)
		return

	# 只留一张护甲：打出后手空且无瞄准，应自动结束进入对手段。
	var armor = null
	var rest: Array = []
	for c in deck.hand:
		if armor == null and c.kind == TacticalActionCardScript.Kind.SKILL_ARMOR:
			armor = c
		else:
			rest.append(c)
	if armor == null:
		for c in deck.draw_pile:
			if c.kind == TacticalActionCardScript.Kind.SKILL_ARMOR:
				armor = c
				deck.draw_pile.erase(c)
				break
		for c in deck.discard_pile:
			if armor != null:
				break
			if c.kind == TacticalActionCardScript.Kind.SKILL_ARMOR:
				armor = c
				deck.discard_pile.erase(c)
				break
	if armor == null:
		armor = TacticalActionCardScript.make_skill_armor()
	for c in rest:
		deck.discard_pile.append(c)
	deck.hand.clear()
	deck.hand.append(armor)
	deck.changed.emit()
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	await process_frame
	await create_timer(0.15).timeout

	if not sandbox.capture_drop_first_card_on_unit("skill_armor", "knight"):
		push_error("PC79 capture: failed to play last armor card on knight")
		quit(1)
		return

	var clock = sandbox.get("_clock")
	var saw_opponent := false
	var skipped_to_player := false
	for _i in 50:
		await process_frame
		await create_timer(0.05).timeout
		if clock == null:
			break
		if not clock.player_active and clock.turn == 1:
			saw_opponent = true
			break
		if clock.player_active and clock.turn >= 2:
			skipped_to_player = true
			break

	if skipped_to_player:
		push_error("PC79 capture: auto-end skipped opponent into player turn %d" % clock.turn)
		quit(2)
		return
	if not saw_opponent:
		push_error("PC79 capture: empty hand should auto-end into opponent turn")
		quit(1)
		return

	var banner = sandbox.get("_turn_banner_panel")
	if banner != null:
		banner.modulate.a = 1.0
	sandbox.set("_last_log", "手牌已打完 · 自动结束行动")
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	await process_frame
	await process_frame
	await create_timer(0.25).timeout

	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("PC79 capture: null viewport image")
		quit(1)
		return
	var err := img.save_png(out_path)
	if err != OK:
		push_error("PC79 capture: save failed %s" % err)
		quit(1)
		return
	print(
		"PC79_CAPTURE_OK player_active=%s hand=%d turn=%d ending=%s %s"
		% [
			clock.player_active,
			deck.hand.size(),
			clock.turn,
			sandbox.get("_ending_player_action"),
			out_path,
		]
	)
	quit(0)
