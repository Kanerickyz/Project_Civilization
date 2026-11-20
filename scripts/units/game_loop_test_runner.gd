extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalEnemyAiScript := preload("res://scripts/units/tactical_enemy_ai.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")
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
	if not _test_wolf_action_preview_overlay_cells():
		quit(1)
		return
	if not _test_wolf_intent_preview_readonly():
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
	if not _test_wolf_melee_range_one():
		quit(1)
		return
	if not _test_wolf_initial_intent_random():
		quit(1)
		return
	print("GAME_LOOP_OK")
	quit(0)


func _test_basic_attack() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var player: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "knight":
			player = u
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "rider":
			foe = u
	if player == null or foe == null:
		push_error("GameLoop: missing units for attack test")
		return false
	# 放到空邻格，避免与其它友方（刺客等）叠格导致 unit_at 命中隐身单位。
	var dest := player.cell + Vector2i(1, 0)
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1)]:
		var c: Vector2i = player.cell + d
		if board.unit_at(c) == null and board.is_passable(c):
			dest = c
			break
	foe.cell = dest
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
	var cell := attacker.cell + Vector2i(1, 0)
	# 清开目标格，避免叠格导致击杀后 unit_at 仍非空。
	for u in board.living_units():
		if u != victim and u != attacker and u.cell == cell:
			u.cell = Vector2i(0, 0) if attacker.cell != Vector2i(0, 0) else Vector2i(0, 1)
	victim.cell = cell
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


func _test_wolf_action_preview_overlay_cells() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rider: TacticalUnitInstance = null
	for u in board.living_units():
		if TacticalEnemyAiScript.uses_behavior_sm(u):
			rider = u
			break
	if rider == null:
		push_error("GameLoop: missing wolf rider for action preview")
		return false
	# 玩家回合查看时移力可能已耗尽，预览仍应按行动预算封顶展示。
	rider.remaining_move_budget = 0
	var moves := board.preview_reachable_move_cells(
		rider, TacticalEnemyAiScript.MOVE_STEP_CAP
	)
	if moves.is_empty():
		push_error("GameLoop: wolf preview should show move cells with depleted budget")
		return false
	if rider.remaining_move_budget != 0:
		push_error("GameLoop: wolf preview must not mutate remaining_move_budget")
		return false
	for c in moves:
		if GridMathScript.chebyshev(rider.cell, c) > TacticalEnemyAiScript.MOVE_STEP_CAP:
			push_error("GameLoop: wolf preview move beyond MOVE_STEP_CAP")
			return false
	var atk := board.attack_range_cells(rider)
	if atk.is_empty():
		push_error("GameLoop: wolf preview should show attack footprint")
		return false
	for c in atk:
		if GridMathScript.chebyshev(rider.cell, c) > rider.def.attack_range:
			push_error("GameLoop: wolf attack cell out of range")
			return false
	return true


func _test_wolf_intent_preview_readonly() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rider: TacticalUnitInstance = null
	var player: TacticalUnitInstance = null
	for u in board.living_units():
		if TacticalEnemyAiScript.uses_behavior_sm(u) and rider == null:
			rider = u
		elif u.faction == TacticalFactionScript.Id.PLAYER and player == null:
			player = u
		else:
			# 清场，避免占格干扰路径/目标预览。
			u.hp = 0
	if rider == null or player == null:
		push_error("GameLoop: missing units for intent preview")
		return false
	rider.attacked_this_side_turn = true
	rider.remaining_move_budget = 0
	player.cell = Vector2i(2, 3)
	# 邻格可打：移动攻击意图应预览到玩家格，且不因本段已攻击标志而失效。
	rider.cell = Vector2i(3, 3)
	rider.next_intent = TacticalEnemyAiScript.Intent.MOVE_ATTACK
	var atk_prev := TacticalEnemyAiScript.preview_next_action(board, rider)
	if String(atk_prev.get("kind", "")) != "attack":
		push_error("GameLoop: intent preview should attack when adjacent")
		return false
	if atk_prev.get("to", Vector2i(-1, -1)) != player.cell:
		push_error("GameLoop: intent preview attack target mismatch")
		return false
	# 远离：移动攻击应给出落点与路径，且不改写状态。
	rider.cell = Vector2i(7, 3)
	rider.next_intent = TacticalEnemyAiScript.Intent.MOVE_ATTACK
	var move_prev := TacticalEnemyAiScript.preview_next_action(board, rider)
	if String(move_prev.get("kind", "")) != "move":
		push_error("GameLoop: intent preview should move when out of range")
		return false
	var dest: Vector2i = move_prev.get("to", Vector2i(-1, -1))
	if dest.x < 0 or dest == rider.cell:
		push_error("GameLoop: intent preview move dest invalid")
		return false
	if GridMathScript.chebyshev(rider.cell, dest) > TacticalEnemyAiScript.MOVE_STEP_CAP:
		push_error("GameLoop: intent preview move beyond MOVE_STEP_CAP")
		return false
	var path: Array = move_prev.get("path", []) as Array
	if path.is_empty():
		push_error("GameLoop: intent preview move path empty")
		return false
	# 回血意图。
	var hurt_hp := maxi(1, rider.effective_max_hp() - 1)
	rider.hp = hurt_hp
	rider.next_intent = TacticalEnemyAiScript.Intent.HEAL
	var heal_prev := TacticalEnemyAiScript.preview_next_action(board, rider)
	if String(heal_prev.get("kind", "")) != "heal":
		push_error("GameLoop: intent preview should heal when not full")
		return false
	# 只读：意图/血量/格/移力不变。
	if (
		rider.next_intent != TacticalEnemyAiScript.Intent.HEAL
		or rider.hp != hurt_hp
		or rider.cell != Vector2i(7, 3)
		or rider.remaining_move_budget != 0
	):
		push_error("GameLoop: intent preview mutated rider state")
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
	# 开战初相已随机；本用例固定移动攻击以验推进到支援相。
	foe.next_intent = TacticalEnemyAiScript.Intent.MOVE_ATTACK
	player.cell = foe.cell + Vector2i(1, 0)
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	var events := TacticalEnemyAiScript.run_opponent_unit_actions(board, foe)
	if events.is_empty() or events[0].get("kind", "") != "attack":
		push_error("GameLoop: rider should execute move-attack intent")
		return false
	var support_ok := (
		foe.next_intent == TacticalEnemyAiScript.Intent.HEAL
		or foe.next_intent == TacticalEnemyAiScript.Intent.BUFF_ATK
	)
	if not support_ok:
		push_error("GameLoop: after move-attack intent should advance to support")
		return false
	return true


## 开战初相：移动攻击 / 支援独立随机；固定种子应覆盖两相。
func _test_wolf_initial_intent_random() -> bool:
	var seen_move_attack := false
	var seen_support := false
	for seed_i in range(64):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_i
		var intent := TacticalEnemyAiScript.roll_initial_intent(rng)
		match intent:
			TacticalEnemyAiScript.Intent.MOVE_ATTACK:
				seen_move_attack = true
			TacticalEnemyAiScript.Intent.HEAL, TacticalEnemyAiScript.Intent.BUFF_ATK:
				seen_support = true
			_:
				push_error("GameLoop: invalid initial intent %d" % intent)
				return false
	if not (seen_move_attack and seen_support):
		push_error(
			"GameLoop: initial intent roll must cover move-attack/support over seeds"
		)
		return false

	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var riders: Array[TacticalUnitInstance] = []
	for u in board.living_units():
		if TacticalEnemyAiScript.uses_behavior_sm(u):
			riders.append(u)
	if riders.size() < 2:
		push_error("GameLoop: need >=2 riders for independent initial intents")
		return false
	for r in riders:
		var ok_intent := (
			r.next_intent == TacticalEnemyAiScript.Intent.MOVE_ATTACK
			or r.next_intent == TacticalEnemyAiScript.Intent.HEAL
			or r.next_intent == TacticalEnemyAiScript.Intent.BUFF_ATK
		)
		if not ok_intent:
			push_error("GameLoop: spawned rider has invalid next_intent")
			return false

	# 多局布阵：至少出现过两种不同初相（避免「全员同一操作」回归）。
	var kinds: Dictionary = {}
	for _i in range(24):
		var b2 := TacticalSandboxRosterScript.build_demo_board(10, 8)
		for u2 in b2.living_units():
			if TacticalEnemyAiScript.uses_behavior_sm(u2):
				kinds[u2.next_intent] = true
	if kinds.size() < 2:
		push_error("GameLoop: spawned riders should not all share one initial intent")
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
	# 满血回血意图应跳过；邻格可攻时落到移动攻击并推进到支援。
	foe.hp = foe.effective_max_hp()
	foe.next_intent = TacticalEnemyAiScript.Intent.HEAL
	player.cell = foe.cell + Vector2i(1, 0)
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	var events := TacticalEnemyAiScript.run_opponent_unit_actions(board, foe)
	if events.is_empty() or events[0].get("kind", "") != "attack":
		push_error("GameLoop: full-hp heal should skip into move-attack")
		return false
	var support_ok := (
		foe.next_intent == TacticalEnemyAiScript.Intent.HEAL
		or foe.next_intent == TacticalEnemyAiScript.Intent.BUFF_ATK
	)
	if not support_ok:
		push_error("GameLoop: after skipped-heal attack should advance to support")
		return false
	return true


## 狼骑兵攻击距离固定 1：距 2 不可攻；邻格可攻（意图「可攻击」与 combat 一致）。
func _test_wolf_melee_range_one() -> bool:
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
	if foe.def.attack_range != 1:
		push_error("GameLoop: rider attack_range must be 1, got %d" % foe.def.attack_range)
		return false

	# 距 2：当前 footprint 不可普攻（攻击距离仍为 1）。
	player.cell = foe.cell + Vector2i(2, 0)
	var far_cells := TacticalCombatScript.attackable_cells(board, foe)
	if not far_cells.is_empty():
		push_error("GameLoop: rider must not attack at chebyshev 2")
		return false

	# 距 4：移动攻击最多靠近 2 格后仍距 2，本段不应打出攻击。
	player.cell = foe.cell + Vector2i(4, 0)
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	foe.next_intent = TacticalEnemyAiScript.Intent.MOVE_ATTACK
	var far_events := TacticalEnemyAiScript.run_opponent_unit_actions(board, foe)
	for ev in far_events:
		if ev.get("kind", "") == "attack":
			push_error("GameLoop: move-attack must not hit from chebyshev 4 in one action")
			return false

	# 邻格（距 1）：可攻。
	player.cell = foe.cell + Vector2i(1, 0)
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	foe.next_intent = TacticalEnemyAiScript.Intent.MOVE_ATTACK
	var near_cells := TacticalCombatScript.attackable_cells(board, foe)
	if near_cells.is_empty() or not near_cells.has(player.cell):
		push_error("GameLoop: rider should attack adjacent cell")
		return false
	var near_events := TacticalEnemyAiScript.run_opponent_unit_actions(board, foe)
	if near_events.is_empty() or near_events[0].get("kind", "") != "attack":
		push_error("GameLoop: move-attack intent should fire at range 1")
		return false
	return true
