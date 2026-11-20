extends SceneTree
## PC-107 GUI：分段血条 + 攻击瞄准伤害链路预览截图。
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc107_hp_preview_capture.gd -- <out.png>

const OUT_DEFAULT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-107-hp-preview.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-107 HP preview")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("pc107 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Node = packed.instantiate()
	root.add_child(sandbox)
	await create_timer(0.45, true, false, true).timeout
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(0.55, true, false, true).timeout

	var board: Variant = sandbox.get("_board")
	var view: Variant = sandbox.get("_board_view")
	if board == null or view == null:
		push_error("pc107 capture: missing board/view")
		quit(1)
		return

	# 摆近战邻格：大剑打狼骑，便于看到伤/击退链路与分段血条。
	var attacker: TacticalUnitInstance = null
	var target: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def != null and u.def.id == "mini_pekka":
			attacker = u
		elif (
			u.faction == TacticalFactionScript.Id.OPPONENT
			and u.def != null
			and u.def.id == "rider"
			and target == null
		):
			target = u
	if attacker == null or target == null:
		push_error("pc107 capture: need mini_pekka + rider")
		quit(1)
		return

	attacker.cell = Vector2i(2, 3)
	target.cell = Vector2i(3, 3)
	# 削一点血，露出空段；目标叠 1 甲，血条甲段可见。
	attacker.hp = maxi(1, attacker.effective_max_hp() - 2)
	target.hp = maxi(3, target.effective_max_hp() - 4)
	target.armor = 1
	board.changed.emit()
	await create_timer(0.2, true, false, true).timeout

	if not sandbox.capture_attack_aim_preview("mini_pekka", "rider"):
		push_error("pc107 capture: attack aim preview failed")
		quit(1)
		return

	view._set_zoom(1.45)
	view._target = view._cell_ground_center(
		Vector2i(
			int(round((float(attacker.cell.x) + float(target.cell.x)) * 0.5)),
			int(round((float(attacker.cell.y) + float(target.cell.y)) * 0.5))
		),
		view.config.cell_size
	)
	view._clamp_target()
	view._apply_camera()

	await create_timer(0.85, true, false, true).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("pc107 capture: save_png failed %s err=%s" % [abs_path, err])
		quit(1)
		return
	print("PC107_HP_PREVIEW_CAPTURE_OK %s" % abs_path)
	quit(0)
