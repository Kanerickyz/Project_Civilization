extends SceneTree
## PC-111 GUI：对手先移动接近时，我方不得提前被击退；死亡 scale 不得大于基准。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc111_knockback_timing_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-111-knockback-after-arrive.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-111 knockback after arrive")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc111 capture: sandbox missing")
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
		push_error("pc111 capture: missing board/view")
		quit(1)
		return

	var player: TacticalUnitInstance = _find_faction_def(
		board, TacticalFactionScript.Id.PLAYER, "knight"
	)
	if player == null:
		player = _any_player(board)
	var foe: TacticalUnitInstance = _find_faction_def(
		board, TacticalFactionScript.Id.OPPONENT, "rider"
	)
	if foe == null:
		foe = _any_enemy(board)
	if player == null or foe == null:
		push_error("pc111 capture: need player + foe")
		quit(1)
		return

	var park := 0
	for u in board.units:
		if not u.is_alive() or u == player or u == foe:
			continue
		u.cell = Vector2i(board.grid_width - 1 - (park % 3), board.grid_height - 1 - int(park / 3))
		park += 1

	# 在可通行横排上找「敌从左两格靠近 → 近战击退一格」。
	var lane := _find_knockback_lane(board)
	if lane.is_empty():
		push_error("pc111 capture: no passable knockback lane on this board")
		quit(1)
		return
	var from_foe: Vector2i = lane["from_foe"]
	var mid_foe: Vector2i = lane["mid_foe"]
	var hit_cell: Vector2i = lane["hit"]
	var kb_to: Vector2i = lane["kb_to"]
	foe.cell = from_foe
	player.cell = hit_cell
	player.hp = maxi(player.effective_max_hp(), 8)
	player.armor = 0
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	await process_frame
	# 等到部署挪位 hop 结束，避免误判为击退 tween。
	await sandbox._await_presentation_idle_async()
	# 与对手段一致：锁输入，避免 board.changed 在 hold 前抢 refresh 播击退。
	sandbox._input_locked = true

	if not board.try_move(foe, mid_foe):
		push_error("pc111 capture: foe move to mid failed")
		quit(1)
		return
	var atk_res: Dictionary = TacticalCombatScript.try_basic_attack(
		board, foe, hit_cell, TacticalFactionScript.Id.OPPONENT
	)
	if not bool(atk_res.get("ok", false)):
		push_error("pc111 capture: attack failed %s" % atk_res)
		quit(1)
		return
	if not bool(atk_res.get("knockback_moved", false)):
		push_error("pc111 capture: expected knockback_moved, got %s" % atk_res)
		quit(1)
		return
	var kb_from: Vector2i = atk_res.get("knockback_from", Vector2i(-1, -1)) as Vector2i
	if kb_from != hit_cell or player.cell != kb_to:
		push_error(
			"pc111 capture: knockback cells mismatch from=%s to=%s player=%s"
			% [kb_from, atk_res.get("knockback_to"), player.cell]
		)
		quit(1)
		return

	# 直接 hold（与沙盘 collect 路径等价），再播移动 refresh。
	view.hold_unit_visual_at_cell(player, kb_from)
	if not view.is_unit_presentation_held(player):
		push_error("pc111 capture: hold_unit_visual_at_cell failed")
		quit(1)
		return

	sandbox._refresh_all()
	await process_frame
	await create_timer(0.08, true, false, true).timeout

	if not view.is_unit_presentation_held(player):
		push_error("pc111 capture: player should be held at hit cell")
		quit(1)
		return
	if view._unit_move_tweens.has(player):
		push_error("pc111 capture: player must not be path-tweening while held")
		quit(1)
		return
	var spr: Sprite2D = view._unit_sprites[player] as Sprite2D
	var from_tile: Node2D = view._tile_nodes.get(kb_from) as Node2D
	if from_tile == null or spr.get_parent() != from_tile:
		push_error(
			"pc111 capture: player left hit cell during enemy move parent=%s"
			% (spr.get_parent() if spr != null else null)
		)
		quit(1)
		return
	var hit_world: Vector2 = view._cell_to_world(kb_from, view.config.cell_size)
	var kb_world: Vector2 = view._cell_to_world(kb_to, view.config.cell_size)
	var world_now: Vector2 = view._unit_world_position(spr)
	if world_now.distance_to(hit_world) > 0.08:
		push_error(
			"pc111 capture: player not at hit cell world hit=%s now=%s"
			% [hit_world, world_now]
		)
		quit(1)
		return
	if world_now.distance_to(kb_world) < world_now.distance_to(hit_world):
		push_error("pc111 capture: player closer to knockback dest than hit cell")
		quit(1)
		return

	_zoom_on(view, foe.cell, kb_from, 1.85)
	await process_frame
	if not _save_frame(out_path):
		quit(1)
		return

	# 走完移动后再攻击与击退，确认 hold 解除。
	await sandbox._await_presentation_idle_async()
	var tw: Tween = view.play_unit_attack(foe, kb_from)
	if tw != null:
		await tw.finished
	await sandbox._feedback_from_attack(player, atk_res, kb_from)
	if view.is_unit_presentation_held(player):
		push_error("pc111 capture: knockback hold not released after attack")
		quit(1)
		return

	print("PC111_KNOCKBACK_TIMING_CAPTURE_OK out=%s" % out_path)
	quit(0)


func _find_knockback_lane(board: Variant) -> Dictionary:
	for y in range(board.grid_height):
		for x in range(board.grid_width - 3):
			var from_foe := Vector2i(x, y)
			var mid_foe := Vector2i(x + 1, y)
			var hit := Vector2i(x + 2, y)
			var kb_to := Vector2i(x + 3, y)
			var ok := true
			for c in [from_foe, mid_foe, hit, kb_to]:
				if not board.is_passable(c):
					ok = false
					break
			if ok:
				return {
					"from_foe": from_foe,
					"mid_foe": mid_foe,
					"hit": hit,
					"kb_to": kb_to,
				}
	return {}


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
		push_error("pc111 capture: null image")
		return false
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("pc111 capture: save failed %s" % path)
		return false
	return true
