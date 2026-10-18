extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")


func _initialize() -> void:
	if not _test_roster_loads():
		quit(1)
		return
	if not _test_knight_damage_and_buff():
		quit(1)
		return
	if not _test_wardrum_allies():
		quit(1)
		return
	if not _test_pekka_kill_stack():
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


func _test_knight_damage_and_buff() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "archer")
	if knight == null or foe == null:
		push_error("TacticalUnits: knight/archer missing")
		return false
	foe.cell = Vector2i(2, 2)
	var before_hp := foe.hp
	var before_atk := knight.effective_attack()
	var res := TacticalAbilitySystemScript.cast(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"]:
		push_error("TacticalUnits: knight cast failed %s" % res["log"])
		return false
	if foe.hp >= before_hp:
		push_error("TacticalUnits: knight should deal damage")
		return false
	if knight.effective_attack() != before_atk + 1:
		push_error("TacticalUnits: knight should gain +1 atk")
		return false
	return true


func _test_wardrum_allies() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var drum := _player_unit(board, "wardrum")
	var archer := _player_unit(board, "archer")
	if drum == null or archer == null:
		return false
	if GridMathScript.chebyshev(drum.cell, archer.cell) > 2:
		push_error("TacticalUnits: archer should be in drum radius for demo layout")
		return false
	var before := archer.effective_attack()
	var res := TacticalAbilitySystemScript.cast(
		board, drum, drum.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"]:
		push_error("TacticalUnits: wardrum cast failed")
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
	foe.cell = pekka.cell + Vector2i(0, 1)
	foe.hp = 1
	var before := pekka.effective_attack()
	var res := TacticalAbilitySystemScript.cast(
		board, pekka, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"] or foe.is_alive():
		push_error("TacticalUnits: pekka should kill weak archer")
		return false
	if pekka.effective_attack() != before + 2:
		push_error("TacticalUnits: pekka kill should +2 atk")
		return false
	return true
