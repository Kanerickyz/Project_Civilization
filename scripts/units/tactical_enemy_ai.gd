class_name TacticalEnemyAi
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalUnitInstanceScript := preload("res://scripts/units/tactical_unit_instance.gd")

## 敌方行为状态机：移动攻击合一 →（支援相）循环；各单位独立相位。
## 狼骑兵支援：回血 | 加攻；骷髅将军支援：回血 | 召唤骷髅兵。
## 「可攻击」一律走 TacticalCombat.attackable_cells（近战邻格 + LOS）。

enum Intent { MOVE_ATTACK, HEAL, BUFF_ATK, SUMMON }

const RIDER_ID := "rider"
const SKELETON_GENERAL_ID := "skeleton_general"
const SKELETON_SOLDIER_PATH := "res://resources/units/skeleton_soldier.tres"
const HEAL_AMOUNT := 2
const BUFF_ATK_AMOUNT := 2
const SUMMON_COUNT := 2
## 移动攻击意图中靠近步数上限（≠ 攻击距离；攻击距离见各单位 attack_range）。
const MOVE_STEP_CAP := 2
const _UNREACHABLE_BASE := 10000


static func uses_behavior_sm(unit: TacticalUnitInstance) -> bool:
	return (
		unit != null
		and unit.is_alive()
		and unit.faction == TacticalFactionScript.Id.OPPONENT
		and unit.def != null
		and is_sm_unit_id(unit.def.id)
	)


static func is_sm_unit_id(unit_id: String) -> bool:
	return unit_id == RIDER_ID or unit_id == SKELETON_GENERAL_ID


static func is_skeleton_general(unit: TacticalUnitInstance) -> bool:
	return unit != null and unit.def != null and unit.def.id == SKELETON_GENERAL_ID


static func intent_name(intent: int) -> String:
	match intent:
		Intent.MOVE_ATTACK:
			return "移动攻击"
		Intent.HEAL:
			return "回血"
		Intent.BUFF_ATK:
			return "加攻"
		Intent.SUMMON:
			return "召唤"
		_:
			return "?"


## 开战初始意图：从「移动攻击」与支援相中随机；狼骑支援=回血|加攻，将军=回血|召唤。
## 权重约 2:1（合并前攻/移各一档），避免全员同相。
static func roll_initial_intent(
	rng: RandomNumberGenerator = null, unit_id: String = RIDER_ID
) -> int:
	var local_rng := rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.randomize()
	match local_rng.randi_range(0, 2):
		0, 1:
			return Intent.MOVE_ATTACK
		_:
			return _roll_support_intent(local_rng, unit_id)


## 只读预览下一回合将实际执行的行为（含跳过），不改写棋盘、移力与意图。
## 返回：kind=attack|move|heal|buff_atk|summon|idle；from/to；path；amount；summon_cells。
static func preview_next_action(board: TacticalBoard, unit: TacticalUnitInstance) -> Dictionary:
	var idle := _preview_idle(unit)
	if board == null or not uses_behavior_sm(unit):
		return idle
	var intent: int = unit.next_intent
	var scanned: Dictionary = {}
	while true:
		if scanned.has(intent):
			idle["resolved_intent"] = intent
			return idle
		scanned[intent] = true
		match intent:
			Intent.MOVE_ATTACK:
				var atk_to := _preview_attack_target(board, unit)
				if atk_to.x >= 0:
					return _preview_payload("attack", Intent.MOVE_ATTACK, unit.cell, atk_to, [], 0)
				var dest := _preview_move_dest(board, unit)
				if dest.x >= 0 and dest != unit.cell:
					var path := _preview_move_path(board, unit, dest)
					return _preview_payload("move", Intent.MOVE_ATTACK, unit.cell, dest, path, 0)
				intent = _preview_preferred_support(unit)
			Intent.HEAL:
				var max_hp := unit.effective_max_hp()
				if unit.hp < max_hp:
					var gain := mini(HEAL_AMOUNT, max_hp - unit.hp)
					return _preview_payload("heal", Intent.HEAL, unit.cell, unit.cell, [], gain)
				intent = Intent.MOVE_ATTACK
			Intent.BUFF_ATK:
				return _preview_payload(
					"buff_atk", Intent.BUFF_ATK, unit.cell, unit.cell, [], BUFF_ATK_AMOUNT
				)
			Intent.SUMMON:
				var cells := _preview_summon_cells(board, unit)
				if not cells.is_empty():
					var payload := _preview_payload(
						"summon", Intent.SUMMON, unit.cell, cells[0], [], cells.size()
					)
					payload["summon_cells"] = cells
					return payload
				intent = Intent.MOVE_ATTACK
			_:
				idle["resolved_intent"] = intent
				return idle
	return idle


static func _preview_preferred_support(unit: TacticalUnitInstance) -> int:
	if is_skeleton_general(unit):
		return Intent.HEAL if unit.hp < unit.effective_max_hp() else Intent.SUMMON
	return Intent.HEAL if unit.hp < unit.effective_max_hp() else Intent.BUFF_ATK


static func _preview_idle(unit: TacticalUnitInstance) -> Dictionary:
	var cell := unit.cell if unit != null else Vector2i(-1, -1)
	return {
		"kind": "idle",
		"resolved_intent": -1,
		"from": cell,
		"to": Vector2i(-1, -1),
		"path": [] as Array[Vector2i],
		"amount": 0,
		"summon_cells": [] as Array[Vector2i],
	}


static func _preview_payload(
	kind: String,
	resolved_intent: int,
	from: Vector2i,
	to: Vector2i,
	path: Array[Vector2i],
	amount: int
) -> Dictionary:
	return {
		"kind": kind,
		"resolved_intent": resolved_intent,
		"from": from,
		"to": to,
		"path": path,
		"amount": amount,
		"summon_cells": [] as Array[Vector2i],
	}


## 忽略 attacked_this_side_turn：预览的是下一段对手回合（届时会 reset）。
static func _preview_attack_target(board: TacticalBoard, unit: TacticalUnitInstance) -> Vector2i:
	var cells: Array[Vector2i] = []
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		var dist := GridMathScript.chebyshev(unit.cell, u.cell)
		if not unit.def.is_chebyshev_in_attack_band(dist):
			continue
		if not board.has_attack_los(unit.cell, u.cell):
			continue
		cells.append(u.cell)
	if cells.is_empty():
		return Vector2i(-1, -1)
	return _pick_nearest_attack_target(board, unit, cells)


static func _preview_move_dest(board: TacticalBoard, unit: TacticalUnitInstance) -> Vector2i:
	var budget := mini(unit.def.action_move_budget(), MOVE_STEP_CAP)
	if budget <= 0:
		return Vector2i(-1, -1)
	var saved := unit.remaining_move_budget
	unit.remaining_move_budget = budget
	var dest: Vector2i = _best_step_toward_player(board, unit)
	unit.remaining_move_budget = saved
	return dest


static func _preview_move_path(
	board: TacticalBoard, unit: TacticalUnitInstance, dest: Vector2i
) -> Array[Vector2i]:
	var path := board.shortest_path(unit.cell, dest, MOVE_STEP_CAP, unit)
	if path.is_empty():
		path = board.shortest_path(unit.cell, dest, -1, unit)
	if path.is_empty():
		return [unit.cell, dest] as Array[Vector2i]
	return path


static func _preview_summon_cells(board: TacticalBoard, unit: TacticalUnitInstance) -> Array[Vector2i]:
	return _collect_summon_cells(board, unit, SUMMON_COUNT)


static func sorted_opponents(board: TacticalBoard) -> Array[TacticalUnitInstance]:
	var opponents: Array[TacticalUnitInstance] = []
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			opponents.append(u)
	opponents.sort_custom(func(a: TacticalUnitInstance, b: TacticalUnitInstance) -> bool:
		if a.def.id != b.def.id:
			return a.def.id < b.def.id
		if a.cell.y != b.cell.y:
			return a.cell.y < b.cell.y
		return a.cell.x < b.cell.x
	)
	return opponents


static func run_opponent_turn(
	board: TacticalBoard, rng: RandomNumberGenerator = null
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var local_rng := rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.randomize()
	for unit in sorted_opponents(board):
		events.append_array(run_opponent_unit_actions(board, unit, local_rng))
	return events


static func run_opponent_unit_actions(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	rng: RandomNumberGenerator = null
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if unit == null or not unit.is_alive():
		return events
	if not uses_behavior_sm(unit):
		return _legacy_unit_actions(board, unit)

	var local_rng := rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.randomize()

	var start_intent: int = unit.next_intent
	var scanned: Dictionary = {}
	while unit.is_alive():
		var intent: int = unit.next_intent
		if scanned.has(intent):
			# 整圈不可行：本回合待机，推进一档意图以免永久卡死。
			_advance_intent(unit, local_rng)
			events.append({
				"kind": "idle",
				"unit": unit,
				"intent": start_intent,
				"log": "对手 %s 无可行行为，待机" % unit.def.display_name,
			})
			break
		scanned[intent] = true

		match intent:
			Intent.MOVE_ATTACK:
				var combo := _try_move_attack(board, unit)
				if not combo.is_empty():
					events.append_array(combo)
					_advance_intent(unit, local_rng)
					break
				unit.next_intent = _roll_support_intent(local_rng, unit.def.id)
			Intent.HEAL:
				var heal_ev := _try_heal(board, unit)
				if not heal_ev.is_empty():
					events.append(heal_ev)
					_advance_intent(unit, local_rng)
					break
				unit.next_intent = Intent.MOVE_ATTACK
			Intent.BUFF_ATK:
				var buff_ev := _try_buff_atk(board, unit)
				if not buff_ev.is_empty():
					events.append(buff_ev)
					_advance_intent(unit, local_rng)
					break
				unit.next_intent = Intent.MOVE_ATTACK
			Intent.SUMMON:
				var summon_ev := _try_summon(board, unit)
				if not summon_ev.is_empty():
					events.append(summon_ev)
					_advance_intent(unit, local_rng)
					break
				unit.next_intent = Intent.MOVE_ATTACK
			_:
				unit.next_intent = Intent.MOVE_ATTACK
				break
	return events


## 移动攻击合一：能打则打；否则靠近，靠近后再尝试打。
static func _try_move_attack(
	board: TacticalBoard, unit: TacticalUnitInstance
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var atk_now := _try_attack_nearest(board, unit)
	if not atk_now.is_empty():
		events.append(atk_now)
		return events
	var move_evs := _try_move_toward_nearest(board, unit)
	if move_evs.is_empty():
		return events
	events.append_array(move_evs)
	if unit.is_alive():
		var atk_after := _try_attack_nearest(board, unit)
		if not atk_after.is_empty():
			events.append(atk_after)
	return events


static func _advance_intent(unit: TacticalUnitInstance, rng: RandomNumberGenerator) -> void:
	match unit.next_intent:
		Intent.MOVE_ATTACK:
			unit.next_intent = _roll_support_intent(rng, unit.def.id if unit.def != null else RIDER_ID)
		Intent.HEAL, Intent.BUFF_ATK, Intent.SUMMON:
			unit.next_intent = Intent.MOVE_ATTACK
		_:
			unit.next_intent = Intent.MOVE_ATTACK


static func _roll_support_intent(rng: RandomNumberGenerator, unit_id: String) -> int:
	if unit_id == SKELETON_GENERAL_ID:
		if rng.randi_range(0, 1) == 0:
			return Intent.HEAL
		return Intent.SUMMON
	if rng.randi_range(0, 1) == 0:
		return Intent.HEAL
	return Intent.BUFF_ATK


static func _try_attack_nearest(board: TacticalBoard, unit: TacticalUnitInstance) -> Dictionary:
	var atk_cells := TacticalCombatScript.attackable_cells(board, unit)
	if atk_cells.is_empty():
		return {}
	var best_cell := _pick_nearest_attack_target(board, unit, atk_cells)
	var res := TacticalCombatScript.try_basic_attack(
		board, unit, best_cell, TacticalFactionScript.Id.OPPONENT
	)
	if not res["ok"]:
		return {}
	return {"kind": "attack", "result": res, "unit": unit, "cell": best_cell}


static func _pick_nearest_attack_target(
	board: TacticalBoard, attacker: TacticalUnitInstance, cells: Array[Vector2i]
) -> Vector2i:
	var best_cell := cells[0]
	var best_dist := 999999
	var best_hp := 999999
	for c in cells:
		var t := board.unit_at(c)
		if t == null:
			continue
		var d := GridMathScript.chebyshev(attacker.cell, c)
		if d < best_dist or (d == best_dist and t.hp < best_hp):
			best_dist = d
			best_hp = t.hp
			best_cell = c
	return best_cell


static func _try_move_toward_nearest(
	board: TacticalBoard, unit: TacticalUnitInstance
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if unit.remaining_move_budget <= 0:
		return events
	# 本行为最多靠近 MOVE_STEP_CAP 格。
	var budget_cap := mini(unit.remaining_move_budget, MOVE_STEP_CAP)
	var saved_budget := unit.remaining_move_budget
	unit.remaining_move_budget = budget_cap
	var dest: Vector2i = _best_step_toward_player(board, unit)
	unit.remaining_move_budget = saved_budget
	if dest.x < 0:
		return events
	if dest == unit.cell:
		return events
	var before := unit.cell
	if not board.try_move(unit, dest):
		return events
	if unit.cell == before:
		return events
	events.append({"kind": "move", "unit": unit, "dest": unit.cell, "from": before})
	return events


static func _try_heal(board: TacticalBoard, unit: TacticalUnitInstance) -> Dictionary:
	var max_hp := unit.effective_max_hp()
	if unit.hp >= max_hp:
		return {}
	var before := unit.hp
	unit.hp = mini(max_hp, unit.hp + HEAL_AMOUNT)
	var gained := unit.hp - before
	if gained <= 0:
		return {}
	board.changed.emit()
	return {
		"kind": "heal",
		"unit": unit,
		"amount": gained,
		"log": "对手 %s 恢复 %d 血" % [unit.def.display_name, gained],
	}


static func _try_buff_atk(board: TacticalBoard, unit: TacticalUnitInstance) -> Dictionary:
	unit.atk_bonus += BUFF_ATK_AMOUNT
	board.changed.emit()
	return {
		"kind": "buff_atk",
		"unit": unit,
		"amount": BUFF_ATK_AMOUNT,
		"log": "对手 %s 攻击 +%d" % [unit.def.display_name, BUFF_ATK_AMOUNT],
	}


static func _try_summon(board: TacticalBoard, unit: TacticalUnitInstance) -> Dictionary:
	var soldier_def := load(SKELETON_SOLDIER_PATH) as TacticalUnitDef
	if soldier_def == null:
		return {}
	var cells := _collect_summon_cells(board, unit, SUMMON_COUNT)
	if cells.is_empty():
		return {}
	var spawned: Array[TacticalUnitInstance] = []
	for cell in cells:
		var minion := TacticalUnitInstanceScript.new(
			soldier_def, TacticalFactionScript.Id.OPPONENT, cell
		)
		board.add_unit(minion)
		spawned.append(minion)
	return {
		"kind": "summon",
		"unit": unit,
		"spawned": spawned,
		"cells": cells,
		"amount": spawned.size(),
		"log": "对手 %s 召唤 %d 个骷髅兵" % [unit.def.display_name, spawned.size()],
	}


static func _collect_summon_cells(
	board: TacticalBoard, unit: TacticalUnitInstance, want: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if board == null or unit == null or want <= 0:
		return out
	var candidates: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var cell := unit.cell + Vector2i(dx, dy)
			if not board.is_passable(cell):
				continue
			if board.unit_at(cell) != null:
				continue
			candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for c in candidates:
		out.append(c)
		if out.size() >= want:
			break
	return out


static func _legacy_unit_actions(
	board: TacticalBoard, unit: TacticalUnitInstance
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	while unit.is_alive():
		var atk_cells := TacticalCombatScript.attackable_cells(board, unit)
		if not atk_cells.is_empty():
			var best_cell := _pick_nearest_attack_target(board, unit, atk_cells)
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


static func _best_step_toward_player(
	board: TacticalBoard, unit: TacticalUnitInstance
) -> Vector2i:
	var unreachable := Vector2i(-1, -1)
	var reachable := board.reachable_move_cells(unit)
	if reachable.is_empty():
		return unreachable
	var players: Array[TacticalUnitInstance] = []
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		# 隐身单位对敌不可见，不作为靠近目标。
		if u.is_stealthed():
			continue
		players.append(u)
	if players.is_empty():
		return reachable[0]

	var player_dist: Array[Dictionary] = []
	for p in players:
		player_dist.append(board.path_distances_from(p.cell))
	var best_dest: Vector2i = reachable[0]
	var best_dist := 999999
	for dest in reachable:
		var min_d := 999999
		for i in players.size():
			var d: int = int(
				player_dist[i].get(
					dest, _UNREACHABLE_BASE + GridMathScript.chebyshev(dest, players[i].cell)
				)
			)
			min_d = mini(min_d, d)
		if min_d < best_dist:
			best_dist = min_d
			best_dest = dest
	# 若最近可达点并不比当前位置更近，则移动无意义 → 判不可执行。
	var cur_min := 999999
	for i in players.size():
		var cd: int = int(
			player_dist[i].get(
				unit.cell, _UNREACHABLE_BASE + GridMathScript.chebyshev(unit.cell, players[i].cell)
			)
		)
		cur_min = mini(cur_min, cd)
	if best_dist >= cur_min:
		return unreachable
	return best_dest
