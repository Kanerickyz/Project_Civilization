extends SceneTree
## PC-109 GUI：对手移动途中，逻辑已死的我方仍可见（未提前拆精灵）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc109_enemy_arrive_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-109-enemy-arrive-before-kill.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalEnemyAiScript := preload("res://scripts/units/tactical_enemy_ai.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-109 enemy arrive before kill")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc109 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await create_timer(0.4, true, false, true).timeout
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(0.5, true, false, true).timeout
	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0
	_hide_chrome(sandbox)

	var board: Variant = sandbox.get("_board")
	var view: Variant = sandbox.get("_board_view")
	if board == null or view == null:
		push_error("pc109 capture: missing board/view")
		quit(1)
		return

	var player: TacticalUnitInstance = _find_faction_def(board, TacticalFactionScript.Id.PLAYER, "knight")
	if player == null:
		player = _any_player(board)
	var foe: TacticalUnitInstance = _find_faction_def(board, TacticalFactionScript.Id.OPPONENT, "rider")
	if foe == null:
		foe = _any_enemy(board)
	if player == null or foe == null:
		push_error("pc109 capture: need player + foe")
		quit(1)
		return

	# 清空战场干扰：其余单位挪远，只留一对「距 2 → 先移再攻」。
	var park := 0
	for u in board.units:
		if not u.is_alive() or u == player or u == foe:
			continue
		u.cell = Vector2i(board.grid_width - 1 - (park % 3), board.grid_height - 1 - int(park / 3))
		park += 1
	var atk_range := int(foe.def.attack_range) if foe.def != null else 1
	# 放在射程外 1 格：本段必须先移动才能打到。
	player.cell = Vector2i(4, 4)
	foe.cell = Vector2i(maxi(0, 4 - (atk_range + 1)), 4)
	player.hp = 1
	player.armor = 0
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	foe.next_intent = TacticalEnemyAiScript.Intent.MOVE_ATTACK
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	await process_frame

	var dist_before := maxi(absi(foe.cell.x - player.cell.x), absi(foe.cell.y - player.cell.y))
	if dist_before <= atk_range:
		push_error(
			"pc109 capture: foe already in range dist=%s range=%s"
			% [dist_before, atk_range]
		)
		quit(1)
		return

	var events: Array = TacticalEnemyAiScript.run_opponent_unit_actions(board, foe)
	var kinds: Array[String] = []
	for ev in events:
		kinds.append(str(ev.get("kind", "")))
	if not kinds.has("move") or not kinds.has("attack"):
		push_error(
			"pc109 capture: expected move+attack events, got %s foe=%s@%s player@%s range=%s"
			% [
				str(kinds),
				foe.def.id if foe.def != null else "?",
				str(foe.cell),
				str(player.cell),
				foe.def.attack_range if foe.def != null else -1,
			]
		)
		quit(1)
		return
	if player.is_alive():
		push_error("pc109 capture: attack should have killed player in logic batch")
		quit(1)
		return

	# 与沙盘一致：后续击杀目标 hold，再播移动。
	for victim in sandbox._collect_attack_event_kill_victims(events):
		view.hold_dead_unit_visual(victim)
	if not view.is_dead_unit_visual_held(player):
		push_error("pc109 capture: player should be held after logic kill")
		quit(1)
		return

	# 播移动段 refresh（若无 hold，此处会拆掉我方精灵）。
	sandbox._refresh_all()
	await process_frame
	if not view._unit_sprites.has(player):
		push_error("pc109 capture: player sprite removed during enemy move refresh")
		quit(1)
		return
	if not view._unit_move_tweens.has(foe) and view.unit_move_duration_sec() <= 0.0:
		# 允许已极短；至少确认 hold 仍在。
		if not view.is_dead_unit_visual_held(player):
			push_error("pc109 capture: hold lost after move refresh")
			quit(1)
			return

	await create_timer(0.08, true, false, true).timeout
	if not view._unit_sprites.has(player):
		push_error("pc109 capture: player disappeared mid enemy approach")
		quit(1)
		return
	# 死亡表现尚未开始。
	if view.is_unit_dying(player):
		push_error("pc109 capture: death started before enemy attack presentation")
		quit(1)
		return

	_zoom_on(view, foe.cell, player.cell, 1.85)
	await process_frame
	if not _save_frame(out_path):
		quit(1)
		return

	# 走完移动 → 攻击 → 死亡，确认 hold 解除且最终拆掉。
	await sandbox._await_presentation_idle_async()
	var atk_ev: Dictionary = {}
	for ev in events:
		if str(ev.get("kind", "")) == "attack":
			atk_ev = ev
			break
	var cell: Vector2i = atk_ev.get("cell", player.cell) as Vector2i
	var res: Dictionary = atk_ev.get("result", {}) as Dictionary
	var tw: Tween = view.play_unit_attack(foe, cell)
	if tw != null:
		await tw.finished
	await sandbox._feedback_from_attack(player, res, cell)
	await sandbox._await_presentation_idle_async()
	if view._unit_sprites.has(player):
		push_error("pc109 capture: player sprite should be gone after death")
		quit(1)
		return

	print("PC109_ENEMY_ARRIVE_CAPTURE_OK out=%s" % out_path)
	quit(0)


func _any_player(board: Variant) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			return u
	return null


func _any_enemy(board: Variant) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			return u
	return null


func _find_faction_def(board: Variant, faction: int, def_id: String) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == faction and u.def != null and u.def.id == def_id:
			return u
	return null


func _zoom_on(view: Variant, a: Vector2i, b: Vector2i, zoom: float) -> void:
	view._set_zoom(zoom)
	view._target = view._cell_ground_center(
		Vector2i(
			int(round((float(a.x) + float(b.x)) * 0.5)),
			int(round((float(a.y) + float(b.y)) * 0.5))
		),
		view.config.cell_size
	)
	view._clamp_target()
	view._apply_camera()


func _hide_chrome(sandbox: Control) -> void:
	for key in ["_hand_fan", "_end_turn_button", "_cancel_target_button", "_bottom_bar", "_side_panel"]:
		var node: Variant = sandbox.get(key)
		if node is CanvasItem:
			(node as CanvasItem).visible = false


func _save_frame(path: String) -> bool:
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("pc109 capture: null image")
		return false
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("pc109 capture: save failed %s" % path)
		return false
	return true
