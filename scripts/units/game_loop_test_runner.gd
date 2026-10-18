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
	if not _test_reachable_and_attack_overlay_cells():
		quit(1)
		return
	if not _test_victory_detection():
		quit(1)
		return
	if not _test_opponent_ai_runs():
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
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "knight":
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
