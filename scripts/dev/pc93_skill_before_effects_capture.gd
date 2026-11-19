extends SceneTree
## PC-93 GUI：① 鼓手先技能后同步加攻；② 同批多死多剪影各锚死亡位。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc93_skill_before_effects_capture.gd -- <out.png> [multi_out.png]

const OUT_DEFAULT := (
	"/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-93-skill-before-effects.png"
)
const MULTI_OUT_DEFAULT := (
	"/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-93-multi-kill-silhouettes.png"
)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else OUT_DEFAULT
	var multi_out := String(args[1]) if args.size() > 1 else MULTI_OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(multi_out.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-93 skill before effects")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc93 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Node = packed.instantiate()
	root.add_child(sandbox)
	await create_timer(0.4, true, false, true).timeout
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(0.5, true, false, true).timeout

	var board: Variant = sandbox.get("_board")
	var view: Variant = sandbox.get("_board_view")
	if board == null or view == null:
		push_error("pc93 capture: missing board/view")
		quit(1)
		return

	var drum: TacticalUnitInstance = null
	var archer: TacticalUnitInstance = null
	var knight: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFaction.Id.PLAYER:
			continue
		match u.def.id:
			"wardrum":
				drum = u
			"archer":
				archer = u
			"knight":
				knight = u
	if drum == null or archer == null or knight == null:
		push_error("pc93 capture: need wardrum+archer+knight")
		quit(1)
		return

	drum.cell = Vector2i(2, 3)
	archer.cell = Vector2i(3, 3)
	knight.cell = Vector2i(2, 4)
	board.changed.emit()
	await create_timer(0.2, true, false, true).timeout

	var fx: Array = []
	var logs := TacticalAbilitySystem.process_player_attack_card_played(board, fx)
	if logs.is_empty() or fx.is_empty():
		push_error("pc93 capture: expected wardrum fx, logs=%s fx=%s" % [logs, fx])
		quit(1)
		return
	var first: Dictionary = fx[0] as Dictionary
	if str(first.get("kind", "")) != "skill_prompt" or str(first.get("text", "")) != "战鼓同频":
		push_error("pc93 capture: first fx must be skill_prompt 战鼓同频, got %s" % [fx])
		quit(1)
		return
	var atk_n := 0
	var hp_n := 0
	for ev in fx:
		if not (ev is Dictionary):
			continue
		var d: Dictionary = ev as Dictionary
		if str(d.get("sync", "")) == "buff_atk":
			atk_n += 1
		elif str(d.get("sync", "")) == "buff_hp":
			hp_n += 1
	if atk_n < 2 or hp_n < 2:
		push_error("pc93 capture: need sync atk/hp for 2 allies, got %s" % [fx])
		quit(1)
		return

	sandbox.set("_input_locked", true)
	sandbox.set("_last_log", "先技能后效果 · 同类同步")
	var banner: Variant = sandbox.get("_turn_banner_panel")
	if banner != null:
		banner.modulate.a = 0.0
	sandbox.call("_refresh_all")
	await process_frame

	if sandbox.has_method("_play_skill_fx_async"):
		sandbox.call("_play_skill_fx_async", fx)
	# 抖动约 0.36s + 批间隔 0.4s → 截在全体同步 +攻 弹出峰值（+血 尚未弹）。
	await create_timer(0.88, true, false, true).timeout
	await process_frame
	await process_frame

	var img: Image = null
	if view.get("_viewport") != null:
		img = view._viewport.get_texture().get_image()
	if img == null:
		img = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path) if out_path.begins_with("res://") else out_path
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc93 capture: save_png %s failed (%d)" % [abs_path, err])
		quit(1)
		return
	print(
		"PC93_SKILL_BEFORE_EFFECTS_CAPTURE_OK fx=%d atk_sync=%d hp_sync=%d %s"
		% [fx.size(), atk_n, hp_n, abs_path]
	)

	# —— 同批多死：两条狼骑剪影各锚死亡位 ——
	var foes: Array = []
	for u in board.living_units():
		if u.faction == TacticalFaction.Id.OPPONENT and foes.size() < 2:
			foes.append(u)
	if foes.size() < 2:
		push_error("pc93 capture: need 2 living enemies for multi-kill")
		quit(1)
		return
	if not sandbox.has_method("capture_play_kill_impacts"):
		push_error("pc93 capture: capture_play_kill_impacts missing")
		quit(1)
		return
	if not sandbox.capture_play_kill_impacts(foes):
		push_error("pc93 capture: multi kill impact not visible")
		quit(1)
		return
	await create_timer(0.08, true, false, true).timeout
	await process_frame
	await process_frame
	var fx_kill: Control = sandbox.get("_kill_impact") as Control
	if fx_kill == null or not fx_kill.visible:
		push_error("pc93 capture: kill impact not flashing")
		quit(1)
		return
	var sil_n := 0
	if fx_kill.has_method("silhouette_count"):
		sil_n = int(fx_kill.call("silhouette_count"))
	if sil_n < 2:
		push_error("pc93 capture: expected >=2 silhouettes, got %d" % sil_n)
		quit(1)
		return
	# 击杀层挂在沙盘根上，须抓窗口 viewport（勿用棋盘 SubViewport）。
	var img2: Image = root.get_viewport().get_texture().get_image()
	if img2 == null:
		push_error("pc93 capture: null root viewport image")
		quit(1)
		return
	var multi_abs := (
		ProjectSettings.globalize_path(multi_out) if multi_out.begins_with("res://") else multi_out
	)
	var err2 := img2.save_png(multi_abs)
	if err2 != OK:
		push_error("pc93 capture: multi save_png failed %s (%d)" % [multi_abs, err2])
		quit(1)
		return
	print("PC93_MULTI_KILL_CAPTURE_OK silhouettes=%d %s" % [sil_n, multi_abs])
	quit(0)
