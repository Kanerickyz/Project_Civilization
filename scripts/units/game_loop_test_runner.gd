extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalEnemyAiScript := preload("res://scripts/units/tactical_enemy_ai.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TurnClockScript := preload("res://scripts/core/turn_clock.gd")


func _initialize() -> void:
	if not _test_basic_attack():
		quit(1)
		return
	if not _test_kill_result_keeps_target_when_unit_at_null():
		quit(1)
		return
	if not _test_reachable_and_attack_overlay_cells():
		quit(1)
		return
	if not _test_victory_detection():
		quit(1)
		return
	if not _test_opponent_ai_runs():
		quit(1)
		return
	if not _test_attack_flag_resets_with_side_turn():
		quit(1)
		return
	if not _test_wolf_intent_attack_then_advance():
		quit(1)
		return
	if not _test_wolf_intent_heal_skip_when_full():
		quit(1)
		return
	print("GAME_LOOP_OK")
	quit(0)


func _test_basic_attack() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var player: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and player == null:
			player = u
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "rider":
			foe = u
	if player == null or foe == null:
		push_error("GameLoop: missing units for attack test")
		return false
	foe.cell = player.cell + Vector2i(1, 0)
	var before := foe.hp
	var res := TacticalCombatScript.try_basic_attack(
		board, player, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"] or foe.hp >= before:
		push_error("GameLoop: basic attack should deal damage")
		return false
	return true


## 击杀后 unit_at 为 null；结算须保留 target，供对手段清牌/死亡表现（PC-32）。
func _test_kill_result_keeps_target_when_unit_at_null() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var attacker: TacticalUnitInstance = null
	var victim: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and attacker == null:
			attacker = u
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "wardrum":
			victim = u
	if attacker == null or victim == null:
		push_error("GameLoop: missing rider/wardrum for kill-target test")
		return false
	victim.hp = 1
	victim.cell = attacker.cell + Vector2i(1, 0)
	var cell := victim.cell
	var res := TacticalCombatScript.try_basic_attack(
		board, attacker, cell, TacticalFactionScript.Id.OPPONENT
	)
	if not res["ok"] or not res.get("killed", false):
		push_error("GameLoop: expected kill on 1-hp wardrum")
		return false
	if board.unit_at(cell) != null:
		push_error("GameLoop: unit_at should be null after kill")
		return false
	var kept: TacticalUnitInstance = res.get("target") as TacticalUnitInstance
	if kept != victim:
		push_error("GameLoop: kill result must keep target ref for death cull")
		return false
	return true


func _test_reachable_and_attack_overlay_cells() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var player: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			player = u
			break
	if player == null:
		return false
	var moves := board.reachable_move_cells(player)
	if moves.is_empty():
		push_error("GameLoop: expected move cells for fresh unit")
		return false
	var atk := TacticalCombatScript.attackable_cells(board, player)
	if not atk.is_empty() and not (atk[0] is Vector2i):
		push_error("GameLoop: attack cells type")
		return false
	return true


func _test_victory_detection() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	for u in board.units:
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			u.hp = 0
	if not TacticalCombatScript.faction_defeated(board, TacticalFactionScript.Id.OPPONENT):
		push_error("GameLoop: opponent should be defeated")
		return false
	if TacticalCombatScript.faction_defeated(board, TacticalFactionScript.Id.PLAYER):
		push_error("GameLoop: player should still stand")
		return false
	return true


func _test_opponent_ai_runs() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var clock := TurnClockScript.new()
	clock.end_turn()
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	var events := TacticalEnemyAiScript.run_opponent_turn(board)
	if events == null:
		push_error("GameLoop: AI should return event array")
		return false
	return true


func _test_attack_flag_resets_with_side_turn() -> bool:
	# 对手 AI 的 attacked_this_side_turn 在段重置后可再攻；玩家无该预算。
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var player: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and player == null:
			player = u
		if u.faction == TacticalFactionScript.Id.OPPONENT and foe == null:
			foe = u
	if player == null or foe == null:
		return false
	player.cell = foe.cell + Vector2i(1, 0)
	var res := TacticalCombatScript.try_basic_attack(
		board, foe, player.cell, TacticalFactionScript.Id.OPPONENT
	)
	if not res["ok"] or not foe.attacked_this_side_turn:
		push_error("GameLoop: opponent attack setup failed")
		return false
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	var res2 := TacticalCombatScript.try_basic_attack(
		board, foe, player.cell, TacticalFactionScript.Id.OPPONENT
	)
	if not res2["ok"]:
		push_error("GameLoop: opponent should attack on new side turn after reset")
		return false
	return true


func _test_wolf_intent_attack_then_advance() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var player: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and player == null:
			player = u
		if u.faction == TacticalFactionScript.Id.OPPONENT and foe == null:
			foe = u
	if player == null or foe == null:
		return false
	if foe.next_intent != TacticalEnemyAiScript.Intent.ATTACK:
		push_error("GameLoop: rider should start with attack intent")
		return false
	player.cell = foe.cell + Vector2i(1, 0)
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	var events := TacticalEnemyAiScript.run_opponent_unit_actions(board, foe)
	if events.is_empty() or events[0].get("kind", "") != "attack":
		push_error("GameLoop: rider should execute attack intent")
		return false
	if foe.next_intent != TacticalEnemyAiScript.Intent.MOVE:
		push_error("GameLoop: after attack intent should advance to move")
		return false
	return true


func _test_wolf_intent_heal_skip_when_full() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var player: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and player == null:
			player = u
		if u.faction == TacticalFactionScript.Id.OPPONENT and foe == null:
			foe = u
	if player == null or foe == null:
		return false
	# 满血回血意图应跳过；邻格可攻时落到攻击并推进。
	foe.hp = foe.effective_max_hp()
	foe.next_intent = TacticalEnemyAiScript.Intent.HEAL
	player.cell = foe.cell + Vector2i(1, 0)
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	var events := TacticalEnemyAiScript.run_opponent_unit_actions(board, foe)
	if events.is_empty() or events[0].get("kind", "") != "attack":
		push_error("GameLoop: full-hp heal should skip into attack")
		return false
	if foe.next_intent != TacticalEnemyAiScript.Intent.MOVE:
		push_error("GameLoop: after skipped-heal attack should advance to move")
		return false
	return true
