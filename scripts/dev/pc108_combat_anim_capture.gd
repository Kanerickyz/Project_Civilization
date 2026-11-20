extends SceneTree
## PC-108 GUI：战斗表现时序证据（移动 hop / 击杀剪影锚死亡位 / 反应冲刺）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc108_combat_anim_capture.gd -- <out_dir_or_main.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-108-combat-anim.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var main_out := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	var out_dir := main_out.get_base_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-108 combat anim")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc108 capture: sandbox missing")
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

	var board: Variant = sandbox.get("_board")
	var view: Variant = sandbox.get("_board_view")
	if board == null or view == null:
		push_error("pc108 capture: missing board/view")
		quit(1)
		return

	# 配置 A/B 敌方可能是狼骑或将军；玩家必有游侠/大剑。
	var mover: TacticalUnitInstance = _find_player(board, "archer")
	if mover == null:
		mover = _any_player(board)
	var attacker: TacticalUnitInstance = _find_player(board, "mini_pekka")
	if attacker == null:
		attacker = _find_player(board, "knight")
	if attacker == null:
		attacker = _any_player(board)
	var foe: TacticalUnitInstance = _find_enemy(board, "rider")
	if foe == null:
		foe = _any_enemy(board)
	if mover == null or attacker == null or foe == null:
		push_error(
			"pc108 capture: need player+enemy units (mover=%s atk=%s foe=%s)"
			% [mover, attacker, foe]
		)
		quit(1)
		return
	if mover == attacker:
		# 至少保证移动帧与攻击帧单位不同更易读；不够则仍用同一单位。
		for u in board.living_units():
			if u.faction == TacticalFactionScript.Id.PLAYER and u != attacker:
				mover = u
				break

	# 清空地形，避免湖/林挡路；其余单位挪开以免占格。
	if board.has_method("set_terrain_cells"):
		board.set_terrain_cells({})
	for u in board.units:
		if u != mover and u != attacker and u != foe:
			u.hp = 0
	_vacate_around(board, [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 4), Vector2i(3, 4), Vector2i(1, 5), Vector2i(2, 5)])

	_hide_chrome_for_capture(sandbox)

	# --- 帧1：移动 hop 中途（非瞬移）；头顶应只有分段条、无「6/6 攻」数字 ---
	var from_cell := Vector2i(1, 2)
	var to_cell := Vector2i(3, 2)
	mover.cell = from_cell
	attacker.cell = Vector2i(0, 0)
	foe.cell = Vector2i(5, 5)
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	await process_frame
	await process_frame
	if not _assert_hp_bar_no_digits(view, mover):
		quit(1)
		return
	mover.cell = to_cell
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	await process_frame
	if not view._unit_move_tweens.has(mover):
		push_error("pc108 capture: expected move tween after sync cell change")
		quit(1)
		return
	var spr: Sprite2D = view._unit_sprites[mover] as Sprite2D
	var start_w: Vector2 = view._cell_to_world(from_cell, view.config.cell_size)
	var end_w: Vector2 = view._cell_to_world(to_cell, view.config.cell_size)
	await create_timer(0.18 * 0.45, true, false, true).timeout
	var mid_w: Vector2 = view._unit_world_position(spr)
	var dist_start := mid_w.distance_to(start_w)
	var dist_end := mid_w.distance_to(end_w)
	if dist_start < 0.05 or dist_end < 0.05:
		push_error(
			"pc108 capture: move looks snapped (teleport?) mid=%s start=%s end=%s"
			% [mid_w, start_w, end_w]
		)
		quit(1)
		return
	_zoom_on(view, from_cell, to_cell, 1.7)
	await process_frame
	var move_out := out_dir.path_join("pc-108-combat-anim-move.png")
	if not _save_frame(move_out):
		quit(1)
		return
	await create_timer(view.unit_move_duration_sec() + 0.08, true, false, true).timeout

	# --- 帧2：击杀死亡冻结（不播全屏红带，避免撑满屏）---
	attacker.cell = Vector2i(2, 4)
	foe.cell = Vector2i(3, 4)
	foe.hp = 1
	foe.armor = 0
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	await process_frame
	var death_cell: Vector2i = foe.cell
	var cell_world: Vector2 = view._cell_to_world(death_cell, view.config.cell_size)
	var atk_res: Dictionary = TacticalCombatScript.try_basic_attack(
		board, attacker, foe.cell, TacticalFactionScript.Id.PLAYER, true, 0, 0, false
	)
	if not atk_res.get("ok", false) or not atk_res.get("killed", false):
		push_error("pc108 capture: expected kill, got %s" % atk_res)
		quit(1)
		return
	var death_tw: Tween = view.play_unit_death(foe)
	if death_tw == null:
		push_error("pc108 capture: death tween missing")
		quit(1)
		return
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	await process_frame
	if not view._unit_sprites.has(foe) or not view.is_unit_dying(foe):
		push_error("pc108 capture: dying sprite must survive sync")
		quit(1)
		return
	# 剪影锚点数学仍校验；截图只拍死亡淡出中途，避开红带。
	var expected_anchor: Vector2 = sandbox._unit_kill_silhouette_anchor_local(foe)
	if not expected_anchor.is_finite():
		push_error("pc108 capture: death silhouette anchor not finite")
		quit(1)
		return
	var frozen: Vector2 = view._frozen_death_world.get(foe, Vector2.INF) as Vector2
	if not frozen.is_finite():
		push_error("pc108 capture: missing frozen death world")
		quit(1)
		return
	await create_timer(0.12, true, false, true).timeout
	var dying_spr: Sprite2D = view._unit_sprites[foe] as Sprite2D
	if dying_spr == null or dying_spr.modulate.a >= 0.99 or dying_spr.modulate.a <= 0.05:
		push_error(
			"pc108 capture: expected mid-fade alpha, got %s"
			% (dying_spr.modulate.a if dying_spr != null else -1.0)
		)
		quit(1)
		return
	# 须留在死亡格：挂 tile、世界坐标贴近格心（证明未飞向镜头）。
	var tile: Node2D = view._tile_nodes.get(death_cell) as Node2D
	if tile == null or dying_spr.get_parent() != tile:
		push_error("pc108 capture: dying sprite left death tile (flew layer)")
		quit(1)
		return
	var world_now: Vector2 = view._unit_world_position(dying_spr)
	if world_now.distance_to(cell_world) > 0.08:
		push_error(
			"pc108 capture: dying sprite flew off cell cell=%s now=%s"
			% [cell_world, world_now]
		)
		quit(1)
		return
	_zoom_on(view, death_cell, death_cell, 2.0)
	await process_frame
	if not _save_frame(main_out):
		quit(1)
		return
	var kill_out := out_dir.path_join("pc-108-combat-anim-kill.png")
	if not _save_frame(kill_out):
		quit(1)
		return
	if death_tw != null and is_instance_valid(death_tw):
		await death_tw.finished
	await process_frame

	# --- 帧3：冲刺中途（攻击 lunge）---
	foe.hp = maxi(3, foe.effective_max_hp())
	foe.armor = 0
	attacker.cell = Vector2i(1, 5)
	foe.cell = Vector2i(2, 5)
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	await process_frame
	if not _assert_hp_bar_no_digits(view, attacker):
		quit(1)
		return
	var tw: Tween = view.play_unit_attack(attacker, foe.cell)
	if tw == null:
		push_error("pc108 capture: attack tween missing")
		quit(1)
		return
	await create_timer(0.09, true, false, true).timeout
	_zoom_on(view, attacker.cell, foe.cell, 1.75)
	await process_frame
	var react_out := out_dir.path_join("pc-108-combat-anim-reaction.png")
	if not _save_frame(react_out):
		quit(1)
		return
	await tw.finished

	print(
		"PC108_COMBAT_ANIM_CAPTURE_OK main=%s move=%s kill=%s react=%s"
		% [main_out, move_out, kill_out, react_out]
	)
	quit(0)


func _find_player(board: Variant, def_id: String) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def != null and u.def.id == def_id:
			return u
	return null


func _find_enemy(board: Variant, def_id: String) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def != null and u.def.id == def_id:
			return u
	return null


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


func _vacate_around(board: Variant, cells: Array) -> void:
	for u in board.units:
		if not u.is_alive():
			continue
		for c in cells:
			if u.cell == c:
				# 挪到盘角空位；调用方会再显式摆关切单位。
				u.cell = Vector2i(board.grid_width - 1, board.grid_height - 1)
				break


func _zoom_on(view: Variant, a: Vector2i, b: Vector2i, zoom: float = 1.55) -> void:
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


## 收起手牌/底栏，让棋盘单位与分段血条更清晰（截图专用）。
func _hide_chrome_for_capture(sandbox: Control) -> void:
	if sandbox.get("_hand_fan") != null:
		(sandbox.get("_hand_fan") as CanvasItem).visible = false
	if sandbox.get("_end_turn_button") != null:
		(sandbox.get("_end_turn_button") as CanvasItem).visible = false
	if sandbox.get("_cancel_target_button") != null:
		(sandbox.get("_cancel_target_button") as CanvasItem).visible = false
	if sandbox.get("_bottom_bar") != null:
		(sandbox.get("_bottom_bar") as CanvasItem).visible = false
	if sandbox.get("_side_panel") != null:
		(sandbox.get("_side_panel") as CanvasItem).visible = false


## PC-107：头顶 Text Label 须隐藏且无「攻」数字。
func _assert_hp_bar_no_digits(view: Variant, unit: TacticalUnitInstance) -> bool:
	if unit == null or not view._hp_bars.has(unit):
		push_error("pc108 capture: missing hp bar for assert")
		return false
	var root: Control = view._hp_bars[unit] as Control
	var legacy: Label = root.get_node_or_null("Text") as Label
	if legacy != null and legacy.visible:
		push_error("pc108 capture: legacy HP/ATK text still visible")
		return false
	if legacy != null and not str(legacy.text).is_empty():
		push_error("pc108 capture: legacy HP/ATK text not cleared: %s" % legacy.text)
		return false
	var segs: Node = root.get_node_or_null("Segments")
	if segs == null or segs.get_child_count() <= 0:
		push_error("pc108 capture: expected segmented HP pips")
		return false
	return true


func _save_frame(path: String) -> bool:
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("pc108 capture: null image for %s" % path)
		return false
	var abs_path := ProjectSettings.globalize_path(path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc108 capture: save_png failed %s err=%s" % [abs_path, err])
		return false
	return true
