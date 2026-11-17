extends SceneTree
## PC-51：鸣鼓换手打出后进弃、当回合不洗回的 GUI 截图。


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://pc51_wardrum_discard.png"
	var w := int(args[1]) if args.size() > 1 else 393
	var h := int(args[2]) if args.size() > 2 else 852
	DisplayServer.window_set_size(Vector2i(w, h))
	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc51 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Node = packed.instantiate()
	root.add_child(sandbox)
	await create_timer(0.4, true, false, true).timeout
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(0.5, true, false, true).timeout

	var deck: Variant = sandbox.get("_deck")
	if deck == null:
		push_error("pc51 capture: no deck")
		quit(1)
		return

	# 把手/库/弃里的鸣鼓换手集中到手牌唯一一张，再清空牌库迫使洗弃。
	var skill: TacticalActionCard = null
	var kept_hand: Array = []
	for c in deck.hand:
		if c.kind == TacticalActionCard.Kind.SKILL_DRAW and skill == null:
			skill = c
		else:
			kept_hand.append(c)
	for c in deck.draw_pile:
		if c.kind == TacticalActionCard.Kind.SKILL_DRAW and skill == null:
			skill = c
		else:
			kept_hand.append(c)
	for c in deck.discard_pile:
		if c.kind == TacticalActionCard.Kind.SKILL_DRAW and skill == null:
			skill = c
		else:
			kept_hand.append(c)
	if skill == null:
		skill = TacticalActionCard.make_skill_draw("wardrum")
	deck.hand.clear()
	deck.draw_pile.clear()
	deck.discard_pile.clear()
	for c in kept_hand:
		deck.discard_pile.append(c)
	deck.hand.append(skill)
	# 饲料：保证洗回后能抽满 5。
	while deck.discard_pile.size() < 8:
		deck.discard_pile.append(TacticalActionCard.make_move())
		deck.discard_pile.append(TacticalActionCard.make_attack())
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	await create_timer(0.2, true, false, true).timeout

	var played: TacticalActionCard = deck.play_hand_index(0)
	if played != skill:
		push_error("pc51 capture: unexpected play result")
		quit(1)
		return
	var drawn: int = deck.resolve_wardrum_redraw()
	sandbox.set("_last_log", "鸣鼓换手：弃手后抽 %d 张 · 本卡留弃牌不洗回" % drawn)
	sandbox.set("_focus_unit", null)
	sandbox.set("_selected_unit", null)
	if sandbox.has_method("_refresh_all"):
		sandbox.call("_refresh_all")
	await create_timer(0.35, true, false, true).timeout

	var skill_in_hand := false
	var skill_in_draw := false
	var skill_in_discard := false
	for c in deck.hand:
		if c == skill:
			skill_in_hand = true
	for c in deck.draw_pile:
		if c == skill:
			skill_in_draw = true
	for c in deck.discard_pile:
		if c == skill:
			skill_in_discard = true
	print(
		"PC51_STATE played_in_hand=%s played_in_draw=%s played_in_discard=%s drawn=%d hand=%d"
		% [skill_in_hand, skill_in_draw, skill_in_discard, drawn, deck.hand.size()]
	)
	if skill_in_hand or skill_in_draw or not skill_in_discard:
		push_error("pc51 capture: played skill must stay in discard same turn")
		quit(2)
		return

	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc51 capture: save failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC51_CAPTURE_OK ", abs_path)
	quit(0)
