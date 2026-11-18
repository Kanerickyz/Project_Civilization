extends SceneTree
## PC-63 GUI：第 5 回合缩圈危险区标记。用法：
## godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 786x1704 \
##   --script res://scripts/dev/pc63_map_collapse_capture.gd -- <out.png>

const DEFAULT_OUT := "/cursor/stores/bc-01a14e65-b45b-721a-8343-8cf4d4fbed1b/media/pc-63-map-collapse.png"
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	DisplayServer.window_set_size(Vector2i(786, 1704))
	DisplayServer.window_set_title("PC-63 map collapse")

	var packed: PackedScene = load("res://scenes/main/sandbox.tscn") as PackedScene
	if packed == null:
		push_error("PC63 capture: sandbox missing")
		quit(1)
		return
	var sandbox: Control = packed.instantiate()
	root.add_child(sandbox)
	await process_frame
	await process_frame
	if sandbox.has_method("capture_confirm_deploy"):
		sandbox.capture_confirm_deploy()
	await create_timer(1.2).timeout
	if sandbox._turn_banner_panel != null:
		sandbox._turn_banner_panel.modulate.a = 0.0

	# 快进到第 5 回合玩家段，触发首圈崩塌；拉远镜头看清外环紫罩。
	sandbox._clock.turn = 5
	sandbox._clock.player_active = true
	var newly: Array = sandbox._board.sync_map_collapse(5)
	if newly.is_empty() or sandbox._board.collapse_stage != 1:
		push_error(
			"PC63 capture: expected stage1 collapse, got stage=%d newly=%d"
			% [sandbox._board.collapse_stage, newly.size()]
		)
		quit(1)
		return
	# 把一名己方单位放到左缘危险区，段开始伤可见。
	var player: TacticalUnitInstance = null
	for u in sandbox._board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			player = u
			break
	if player != null:
		player.cell = Vector2i(0, 3)
		player.hp = maxi(player.hp, 8)
	sandbox._board.changed.emit()
	sandbox._refresh_all()
	await create_timer(0.2).timeout

	var danger_events: Array = sandbox._board.process_danger_ticks(TacticalFactionScript.Id.PLAYER)
	for ev in danger_events:
		var cell: Vector2i = ev.get("cell", Vector2i.ZERO)
		var dmg := int(ev.get("damage", 0))
		var unit := ev.get("unit") as TacticalUnitInstance
		if unit != null and dmg > 0:
			sandbox._board_view.play_damage_popup(cell, dmg)
			sandbox._board_view.play_unit_hit(unit)
	sandbox._last_log = "地图崩塌 · 第 %d 圈危险区（伤 %d）" % [
		sandbox._board.collapse_stage,
		sandbox._board.collapse_danger_damage(),
	]
	sandbox._refresh_all()
	await create_timer(0.18).timeout
	await process_frame
	await process_frame

	var svp: Image = sandbox._board_view._viewport.get_texture().get_image()
	if svp == null:
		push_error("PC63 capture: null board image")
		quit(1)
		return
	svp.save_png(out_path)
	print(
		"PC63_CAPTURE_OK stage=%d newly=%d danger_events=%d dmg=%d %s"
		% [
			sandbox._board.collapse_stage,
			newly.size(),
			danger_events.size(),
			sandbox._board.collapse_danger_damage(),
			out_path,
		]
	)
	quit(0)
