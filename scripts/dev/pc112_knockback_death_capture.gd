extends SceneTree
## PC-112：击退 hold 到攻击后 + 死亡不放大。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc112_knockback_death_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-112-knockback-death.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	var out_dir := out_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-112 knockback death")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc112 capture: sandbox missing")
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
		push_error("pc112 capture: missing board/view")
		quit(1)
		return

	var player: TacticalUnitInstance = _any_player(board)
	var foe: TacticalUnitInstance = _any_enemy(board)
	if player == null or foe == null:
		push_error("pc112 capture: need player + foe")
		quit(1)
		return

	var park := 0
	for u in board.units:
		if not u.is_alive() or u == player or u == foe:
			continue
		u.cell = Vector2i(board.grid_width - 1 - (park % 3), board.grid_height - 1 - int(park / 3))
		park += 1

	var lane := _find_knockback_lane(board)
	if lane.is_empty():
		push_error("pc112 capture: no knockback lane")
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
	await sandbox._await_presentation_idle_async()
	sandbox._input_locked = true

	if not board.try_move(foe, mid_foe):
		push_error("pc112 capture: move failed")
		quit(1)
		return
	var atk_res: Dictionary = TacticalCombatScript.try_basic_attack(
		board, foe, hit_cell, TacticalFactionScript.Id.OPPONENT
	)
	if not bool(atk_res.get("ok", false)) or not bool(atk_res.get("knockback_moved", false)):
		push_error("pc112 capture: need knockback attack %s" % atk_res)
		quit(1)
		return
	var kb_from: Vector2i = atk_res.get("knockback_from", Vector2i(-1, -1)) as Vector2i
	view.hold_unit_visual_at_cell(player, kb_from)
	sandbox._refresh_all()
	await process_frame
	await create_timer(0.08, true, false, true).timeout

	# 帧1：敌移动途中，玩家仍在命中格。
	if not view.is_unit_presentation_held(player):
		push_error("pc112 capture: hold lost during enemy move")
		quit(1)
		return
	var spr: Sprite2D = view._unit_sprites[player] as Sprite2D
	var hit_tile: Node2D = view._tile_nodes.get(kb_from) as Node2D
	if hit_tile == null or spr.get_parent() != hit_tile:
		push_error("pc112 capture: player left hit tile during move")
		quit(1)
		return
	_zoom_on(view, foe.cell, kb_from, 1.85)
	await process_frame
	var frame1 := out_dir.path_join("pc-112-knockback-during-approach.png")
	if not _save_frame(frame1):
		quit(1)
		return
	if not _save_frame(out_path):
		quit(1)
		return

	await sandbox._await_presentation_idle_async()
	var atk_tw: Tween = view.play_unit_attack(foe, kb_from)
	if atk_tw != null:
		await atk_tw.finished
	# 受击时仍应 hold 在命中格（mount 走 presentation_cell）。
	var hit_tw: Tween = view.play_unit_hit(player)
	await process_frame
	spr = view._unit_sprites[player] as Sprite2D
	if spr.get_parent() != hit_tile:
		push_error("pc112 capture: hit remounted player off hit tile")
		quit(1)
		return
	if hit_tw != null and is_instance_valid(hit_tw):
		await hit_tw.finished
	view.release_held_unit_visual(player, kb_from)
	sandbox._refresh_all()
	await process_frame

	# 帧2：死亡尺寸——另设一敌方单位击杀并断言不放大。
	var victim: TacticalUnitInstance = foe
	victim.hp = 1
	victim.armor = 0
	view.sync_tactical_units(board.living_units(), Vector2i(-1, -1), [], [])
	await process_frame
	var base: Vector2 = view._compute_unit_base_scale(victim) as Vector2
	view._unit_base_scales[victim] = base
	# 故意 float 再死亡，确认不会巨大化。
	var vspr: Sprite2D = view._unit_sprites[victim] as Sprite2D
	view._float_unit_for_world_tween(vspr)
	var death_tw: Tween = view.play_unit_death(victim)
	if death_tw == null:
		push_error("pc112 capture: death tween missing")
		quit(1)
		return
	await create_timer(0.1, true, false, true).timeout
	vspr = view._unit_sprites[victim] as Sprite2D
	if vspr.get_parent() == view._units_root:
		push_error("pc112 capture: death left sprite on Units layer")
		quit(1)
		return
	if vspr.scale.x > base.x * 1.001 + 0.0001:
		push_error("pc112 capture: death enlarged scale base=%s now=%s" % [base, vspr.scale])
		quit(1)
		return
	_zoom_on(view, victim.cell, victim.cell, 2.0)
	await process_frame
	var frame2 := out_dir.path_join("pc-112-death-no-enlarge.png")
	if not _save_frame(frame2):
		quit(1)
		return
	# 主输出再盖一帧死亡证据。
	if not _save_frame(out_path):
		quit(1)
		return
	if death_tw != null and is_instance_valid(death_tw):
		await death_tw.finished

	print(
		"PC112_KNOCKBACK_DEATH_CAPTURE_OK main=%s approach=%s death=%s"
		% [out_path, frame1, frame2]
	)
	quit(0)


func _find_knockback_lane(board: Variant) -> Dictionary:
	for y in range(board.grid_height):
		for x in range(board.grid_width - 3):
			var cells := [
				Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 2, y), Vector2i(x + 3, y)
			]
			var ok := true
			for c in cells:
				if not board.is_passable(c):
					ok = false
					break
			if ok:
				return {
					"from_foe": cells[0],
					"mid_foe": cells[1],
					"hit": cells[2],
					"kb_to": cells[3],
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
		push_error("pc112 capture: null image")
		return false
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("pc112 capture: save failed %s" % path)
		return false
	return true
