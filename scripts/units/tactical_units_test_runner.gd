extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalCardDeckScript := preload("res://scripts/cards/tactical_card_deck.gd")
const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")


func _initialize() -> void:
	if not _test_roster_loads():
		quit(1)
		return
	if not _test_move_and_attack_ranges():
		quit(1)
		return
	if not _test_archer_kill_grants_card():
		quit(1)
		return
	if not _test_knight_hurt():
		quit(1)
		return
	if not _test_wardrum_move_end_buff():
		quit(1)
		return
	if not _test_pekka_no_passive():
		quit(1)
		return
	if not _test_basic_attack_flag():
		quit(1)
		return
	if not _test_side_turn_resets_attack():
		quit(1)
		return
	if not _test_archer_move_distance_two():
		quit(1)
		return
	print("TACTICAL_UNITS_OK")
	quit(0)


func _test_roster_loads() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	if board.living_units().size() != 9:
		push_error("TacticalUnits: expected 9 units, got %d" % board.living_units().size())
		return false
	var riders := 0
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			if u.def.id != "rider":
				push_error("TacticalUnits: opponent should be rider, got %s" % u.def.id)
				return false
			riders += 1
	if riders != 5:
		push_error("TacticalUnits: expected 5 wolf cavalry, got %d" % riders)
		return false
	return true


func _player_unit(board: TacticalBoard, id: String) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == id:
			return u
	return null


func _opponent_unit(board: TacticalBoard, id: String) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == id:
			return u
	return null


func _test_move_and_attack_ranges() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	if archer == null:
		return false
	var moves := board.reachable_move_cells(archer)
	if moves.is_empty():
		push_error("TacticalUnits: archer should have move options")
		return false
	for c in moves:
		if GridMathScript.chebyshev(archer.cell, c) > archer.def.action_move_budget():
			push_error("TacticalUnits: move cell beyond action move budget")
			return false
	var attacks := board.attack_range_cells(archer)
	if attacks.is_empty():
		push_error("TacticalUnits: archer should show attack footprint")
		return false
	for c in attacks:
		if GridMathScript.chebyshev(archer.cell, c) > archer.def.attack_range:
			push_error("TacticalUnits: attack cell out of range")
			return false
	archer.remaining_move_budget = 0
	if not board.reachable_move_cells(archer).is_empty():
		push_error("TacticalUnits: exhausted move budget should have no move overlay")
		return false
	return true


func _test_archer_kill_grants_card() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var deck: TacticalCardDeck = TacticalCardDeckScript.new()
	board.player_deck = deck
	var archer := _player_unit(board, "archer")
	var foe := _opponent_unit(board, "rider")
	if archer == null or foe == null:
		return false
	foe.hp = 1
	var hand_before := deck.hand.size()
	board.apply_damage(foe, 1, archer)
	if foe.is_alive():
		push_error("TacticalUnits: archer should kill weak foe")
		return false
	if deck.hand.size() != hand_before + 1:
		push_error("TacticalUnits: archer kill should grant ephemeral attack")
		return false
	var c: TacticalActionCard = deck.hand[deck.hand.size() - 1]
	if not c.ephemeral or c.kind != TacticalActionCardScript.Kind.ATTACK:
		push_error("TacticalUnits: granted card must be ephemeral attack")
		return false
	return true


func _test_knight_hurt() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	if knight == null:
		return false
	var before := knight.effective_attack()
	board.apply_damage(knight, 1, null)
	if knight.effective_attack() != before + 1:
		push_error("TacticalUnits: knight hurt should +1 atk")
		return false
	return true


func _test_wardrum_move_end_buff() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var drum := _player_unit(board, "wardrum")
	var archer := _player_unit(board, "archer")
	if drum == null or archer == null:
		return false
	# 放到鼓手旁一格，确保移动后仍在 2 格内。
	archer.cell = drum.cell + Vector2i(1, 0)
	if board.unit_at(archer.cell) != null and board.unit_at(archer.cell) != archer:
		archer.cell = drum.cell + Vector2i(0, 1)
	var before_atk := archer.effective_attack()
	var before_max := archer.effective_max_hp()
	var before_hp := archer.hp
	var dest := drum.cell + Vector2i(-1, 0)
	if board.unit_at(dest) != null:
		dest = drum.cell + Vector2i(0, -1)
	if not board.try_move(drum, dest):
		push_error("TacticalUnits: wardrum move for buff test failed")
		return false
	if GridMathScript.chebyshev(drum.cell, archer.cell) > 2:
		push_error("TacticalUnits: archer should remain in drum radius")
		return false
	if archer.effective_attack() != before_atk + 1:
		push_error("TacticalUnits: wardrum move end should +1 atk nearby")
		return false
	if archer.effective_max_hp() != before_max + 1 or archer.hp != before_hp + 1:
		push_error("TacticalUnits: wardrum move end should +1 hp nearby")
		return false
	# 行动段开始不再鸣鼓。
	var atk_mid := archer.effective_attack()
	TacticalAbilitySystemScript.process_side_turn_start(board, TacticalFactionScript.Id.PLAYER)
	if archer.effective_attack() != atk_mid:
		push_error("TacticalUnits: side turn must not buff via wardrum anymore")
		return false
	return true


func _test_pekka_no_passive() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var pekka := _player_unit(board, "mini_pekka")
	var foe := _opponent_unit(board, "rider")
	if pekka == null or foe == null:
		return false
	if pekka.def.triggered_ability != null:
		push_error("TacticalUnits: mini_pekka should have no passive")
		return false
	foe.hp = 1
	var before := pekka.effective_attack()
	board.apply_damage(foe, 1, pekka)
	if foe.is_alive():
		push_error("TacticalUnits: pekka should kill weak rider")
		return false
	if pekka.effective_attack() != before:
		push_error("TacticalUnits: pekka kill must not grant atk")
		return false
	return true


func _test_basic_attack_flag() -> bool:
	# 玩家无段内攻次标记；对手 AI 仍每段最多 1 攻。
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "rider")
	if knight == null or foe == null:
		return false
	foe.cell = knight.cell + Vector2i(0, 1)
	foe.hp = 99
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"]:
		push_error("TacticalUnits: player basic attack should succeed")
		return false
	if knight.attacked_this_side_turn:
		push_error("TacticalUnits: player attack must not set attacked_this_side_turn")
		return false
	var again := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not again["ok"]:
		push_error("TacticalUnits: player may attack again without side-turn flag")
		return false
	var ally := knight
	ally.cell = foe.cell + Vector2i(0, 1)
	var opp1 := TacticalCombatScript.try_basic_attack(
		board, foe, ally.cell, TacticalFactionScript.Id.OPPONENT
	)
	if not opp1["ok"] or not foe.attacked_this_side_turn:
		push_error("TacticalUnits: opponent attack should set flag")
		return false
	var opp2 := TacticalCombatScript.try_basic_attack(
		board, foe, ally.cell, TacticalFactionScript.Id.OPPONENT
	)
	if opp2["ok"]:
		push_error("TacticalUnits: opponent should not attack twice per side turn")
		return false
	return true


func _test_side_turn_resets_attack() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "rider")
	if knight == null or foe == null:
		return false
	knight.cell = foe.cell + Vector2i(0, 1)
	var res := TacticalCombatScript.try_basic_attack(
		board, foe, knight.cell, TacticalFactionScript.Id.OPPONENT
	)
	if not res["ok"] or not foe.attacked_this_side_turn:
		push_error("TacticalUnits: opponent first attack should succeed and set flag")
		return false
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	if foe.attacked_this_side_turn:
		push_error("TacticalUnits: side turn reset should clear opponent attack flag")
		return false
	if not TacticalCombatScript.can_basic_attack(foe, TacticalFactionScript.Id.OPPONENT):
		push_error("TacticalUnits: opponent should attack again after side turn reset")
		return false
	return true


func _test_archer_move_distance_two() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	if archer == null:
		return false
	if archer.def.move_range != 2 or archer.def.action_move_budget() != 2:
		push_error(
			"TacticalUnits: archer move_range/budget should be 2, got %d/%d"
			% [archer.def.move_range, archer.def.action_move_budget()]
		)
		return false
	var far := archer.cell + Vector2i(3, 0)
	if board.is_passable(far) and board.unit_at(far) == null:
		if board.try_move(archer, far):
			push_error("TacticalUnits: archer must not move 3 with range 2")
			return false
	var mid := archer.cell + Vector2i(2, 0)
	if board.unit_at(mid) != null:
		mid = archer.cell + Vector2i(0, 2)
	if not board.try_move(archer, mid):
		push_error("TacticalUnits: archer should move distance 2")
		return false
	return true
