extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")


func _initialize() -> void:
	if not _test_roster_loads():
		quit(1)
		return
	if not _test_move_and_attack_ranges():
		quit(1)
		return
	if not _test_archer_deploy():
		quit(1)
		return
	if not _test_knight_hurt():
		quit(1)
		return
	if not _test_wardrum_side_turn():
		quit(1)
		return
	if not _test_pekka_kill_stack():
		quit(1)
		return
	if not _test_basic_attack_flag():
		quit(1)
		return
	if not _test_side_turn_resets_attack():
		quit(1)
		return
	if not _test_multi_move_budget():
		quit(1)
		return
	print("TACTICAL_UNITS_OK")
	quit(0)


func _test_roster_loads() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	if board.living_units().size() != 8:
		push_error("TacticalUnits: expected 8 units, got %d" % board.living_units().size())
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


func _test_archer_deploy() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	if archer == null:
		return false
	var before := archer.effective_attack()
	TacticalAbilitySystemScript.process_battle_start(board)
	if archer.effective_attack() != before + 1:
		push_error("TacticalUnits: archer deploy should +1 atk")
		return false
	TacticalAbilitySystemScript.process_battle_start(board)
	if archer.effective_attack() != before + 1:
		push_error("TacticalUnits: deploy trigger should fire once")
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


func _test_wardrum_side_turn() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var drum := _player_unit(board, "wardrum")
	var archer := _player_unit(board, "archer")
	if drum == null or archer == null:
		return false
	if GridMathScript.chebyshev(drum.cell, archer.cell) > 2:
		push_error("TacticalUnits: archer should be in drum radius for demo layout")
		return false
	var before := archer.effective_attack()
	var logs := TacticalAbilitySystemScript.process_side_turn_start(
		board, TacticalFactionScript.Id.PLAYER
	)
	if logs.is_empty():
		push_error("TacticalUnits: wardrum side turn should buff")
		return false
	if archer.effective_attack() != before + 1:
		push_error("TacticalUnits: wardrum should buff nearby ally")
		return false
	return true


func _test_pekka_kill_stack() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var pekka := _player_unit(board, "mini_pekka")
	var foe := _opponent_unit(board, "archer")
	if pekka == null or foe == null:
		return false
	foe.hp = 1
	var before := pekka.effective_attack()
	board.apply_damage(foe, 1, pekka)
	if foe.is_alive():
		push_error("TacticalUnits: pekka should kill weak archer")
		return false
	if pekka.effective_attack() != before + 2:
		push_error("TacticalUnits: pekka kill should +2 atk")
		return false
	return true


func _test_basic_attack_flag() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "archer")
	if knight == null or foe == null:
		return false
	foe.cell = knight.cell + Vector2i(0, 1)
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"]:
		push_error("TacticalUnits: basic attack failed")
		return false
	if not knight.attacked_this_side_turn:
		push_error("TacticalUnits: attack should set flag")
		return false
	var again := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if again["ok"]:
		push_error("TacticalUnits: should not attack twice per side turn")
		return false
	return true


func _test_side_turn_resets_attack() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "archer")
	if knight == null or foe == null:
		return false
	foe.cell = knight.cell + Vector2i(0, 1)
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"] or not knight.attacked_this_side_turn:
		push_error("TacticalUnits: first attack should succeed and set flag")
		return false
	board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	if knight.attacked_this_side_turn:
		push_error("TacticalUnits: side turn reset should clear attack flag")
		return false
	if not TacticalCombatScript.can_basic_attack(knight, TacticalFactionScript.Id.PLAYER):
		push_error("TacticalUnits: should attack again after side turn reset")
		return false
	return true


func _test_multi_move_budget() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	if archer == null:
		return false
	var budget := archer.def.action_move_budget()
	if budget < 2:
		push_error("TacticalUnits: archer needs move budget for multi-step test")
		return false
	var first_dest := archer.cell + Vector2i(1, 0)
	if board.unit_at(first_dest) != null:
		first_dest = archer.cell + Vector2i(0, 1)
	if not board.try_move(archer, first_dest):
		push_error("TacticalUnits: first multi-move step failed")
		return false
	if archer.remaining_move_budget <= 0:
		push_error("TacticalUnits: should have budget after one step")
		return false
	var moves := board.reachable_move_cells(archer)
	if moves.is_empty():
		push_error("TacticalUnits: should still show reachable cells with budget left")
		return false
	return true
