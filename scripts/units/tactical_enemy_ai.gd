class_name TacticalEnemyAi
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

## 对手行动段最小启发式：逐单位行动，能攻则攻，否则消耗移动力向最近玩家靠近。

const _UNREACHABLE_BASE := 10000


static func sorted_opponents(board: TacticalBoard) -> Array[TacticalUnitInstance]:
	var opponents: Array[TacticalUnitInstance] = []
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			opponents.append(u)
	opponents.sort_custom(func(a, b): return a.def.id < b.def.id)
	return opponents


static func run_opponent_turn(board: TacticalBoard) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for unit in sorted_opponents(board):
		events.append_array(run_opponent_unit_actions(board, unit))
	return events


static func run_opponent_unit_actions(board: TacticalBoard, unit: TacticalUnitInstance) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if unit == null or not unit.is_alive():
		return events
	while unit.is_alive():
		var atk_cells := TacticalCombatScript.attackable_cells(board, unit)
		if not atk_cells.is_empty():
			var best_cell := _pick_attack_target(board, unit, atk_cells)
			var res := TacticalCombatScript.try_basic_attack(
				board, unit, best_cell, TacticalFactionScript.Id.OPPONENT
			)
			if res["ok"]:
				events.append({"kind": "attack", "result": res, "unit": unit, "cell": best_cell})
			break
		if unit.remaining_move_budget <= 0:
			break
		var dest: Vector2i = _best_step_toward_player(board, unit)
		if dest.x < 0 or not board.try_move(unit, dest):
			break
		events.append({"kind": "move", "unit": unit, "dest": dest})
	return events


static func _pick_attack_target(
	board: TacticalBoard, attacker: TacticalUnitInstance, cells: Array[Vector2i]
) -> Vector2i:
	var best: TacticalUnitInstance = null
	var best_cell := cells[0]
	for c in cells:
		var t := board.unit_at(c)
		if t == null:
			continue
		if best == null or t.hp < best.hp:
			best = t
			best_cell = c
	return best_cell


static func _best_step_toward_player(
	board: TacticalBoard, unit: TacticalUnitInstance
) -> Vector2i:
	var unreachable := Vector2i(-1, -1)
	var reachable := board.reachable_move_cells(unit)
	if reachable.is_empty():
		return unreachable
	var players: Array[TacticalUnitInstance] = []
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			players.append(u)
	if players.is_empty():
		return reachable[0]

	# 用路径距离（绕墙）而非切比雪夫，避免贴墙卡死；无墙时两者相同。
	var player_dist: Array[Dictionary] = []
	for p in players:
		player_dist.append(board.path_distances_from(p.cell))
	var best_dest: Vector2i = reachable[0]
	var best_dist := 999999
	for dest in reachable:
		var min_d := 999999
		for i in players.size():
			var d: int = int(player_dist[i].get(dest, _UNREACHABLE_BASE + GridMathScript.chebyshev(dest, players[i].cell)))
			min_d = mini(min_d, d)
		if min_d < best_dist:
			best_dist = min_d
			best_dest = dest
	return best_dest
