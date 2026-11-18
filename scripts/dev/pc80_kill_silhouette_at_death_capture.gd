extends SceneTree
## PC-80 GUI：击杀剪影锚在死亡单位屏幕位（非正中）。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc80_kill_silhouette_at_death_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-80-kill-silhouette-at-death.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-80 kill silhouette at death")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC80 capture: sandbox missing")
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
		push_error("PC80 capture: rider texture_red missing")
		quit(1)
		return
	var wolf_tex: Texture2D = rider_def.texture_red

	var anchor_unit: TacticalUnitInstance = _pick_off_center_enemy(sandbox)
	if anchor_unit == null:
		push_error("PC80 capture: no off-center enemy unit")
		quit(1)
		return

	if not sandbox.has_method("capture_play_kill_impact"):
		push_error("PC80 capture: capture_play_kill_impact missing")
		quit(1)
		return
	if not sandbox.capture_play_kill_impact(wolf_tex, anchor_unit):
		push_error("PC80 capture: kill impact not visible")
		quit(1)
		return

	# 截在 hold 峰值（pop 后、fade 前）。
	await create_timer(0.08).timeout
	await process_frame
	await process_frame

	var fx: Control = sandbox._kill_impact as Control
	if fx == null or not fx.visible or fx.modulate.a < 0.5:
		push_error("PC80 capture: expected kill impact flashing")
		quit(1)
		return
	var sil: Texture2D = fx._silhouette_tex as Texture2D
	if sil == null:
		push_error("PC80 capture: expected unit silhouette texture")
		quit(1)
		return
	var anchor: Vector2 = fx._anchor_local as Vector2
	if not is_finite(anchor.x) or not is_finite(anchor.y):
		push_error("PC80 capture: expected finite death anchor, got %s" % anchor)
		quit(1)
		return
	var center := fx.size * 0.5
	var dist := anchor.distance_to(center)
	# 死亡位须明显偏离屏心。
	if dist < 70.0:
		push_error(
			"PC80 capture: silhouette still near center dist=%.1f anchor=%s center=%s"
			% [dist, anchor, center]
		)
		quit(1)
		return
	var expected: Vector2 = sandbox._unit_kill_silhouette_anchor_local(anchor_unit)
	if anchor.distance_to(expected) > 2.0:
		push_error(
			"PC80 capture: anchor %s != unit local %s" % [anchor, expected]
		)
		quit(1)
		return

	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("PC80 capture: null window image")
		quit(1)
		return
	var err := img.save_png(out_path)
	if err != OK:
		push_error("PC80 capture: save_png failed %s err=%s" % [out_path, err])
		quit(1)
		return
	print(
		"PC80_CAPTURE_OK visible=%s alpha=%.2f cell=%s anchor=%s center=%s dist=%.1f %s"
		% [fx.visible, fx.modulate.a, anchor_unit.cell, anchor, center, dist, out_path]
	)
	quit(0)


func _pick_off_center_enemy(sandbox: Control) -> TacticalUnitInstance:
	if sandbox._board == null or sandbox._board_view == null or sandbox._kill_impact == null:
		return null
	var fx: Control = sandbox._kill_impact as Control
	var board: Control = sandbox._board_view as Control
	var center := fx.size * 0.5
	if center.x < 1.0 or center.y < 1.0:
		center = Vector2(393.0, 852.0)
	# 选盘内、明显偏心的敌方（避免贴边/飞出导致剪影看起来贴屏缘）。
	var best: TacticalUnitInstance = null
	var best_score := -1.0
	for u in sandbox._board.units:
		var unit := u as TacticalUnitInstance
		if unit == null or not unit.is_alive():
			continue
		if unit.faction == TacticalFaction.Id.PLAYER:
			continue
		var screen: Vector2 = sandbox._board_view.unit_screen_position(unit)
		var local: Vector2 = fx.get_global_transform_with_canvas().affine_inverse() * screen
		var board_rect := board.get_global_rect().grow(-24.0)
		if not board_rect.has_point(screen):
			continue
		var d := local.distance_to(center)
		if d < 70.0:
			continue
		# 略偏右下更易肉眼对照「非正中」。
		var score := d + maxf(local.x - center.x, 0.0) * 0.35
		if score > best_score:
			best_score = score
			best = unit
	return best
