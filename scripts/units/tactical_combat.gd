class_name TacticalCombat
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")

## 普攻与伤害；不替代主动技系统。


## 玩家无段内攻击次数上限（由攻击卡授权）；对手 AI 仍用 attacked_this_side_turn。
static func can_basic_attack(attacker: TacticalUnitInstance, active_faction: TacticalFaction.Id) -> bool:
	if attacker == null or not attacker.is_alive():
		return false
	if attacker.faction != active_faction:
		return false
	if attacker.faction == TacticalFaction.Id.PLAYER:
		return true
	return not attacker.attacked_this_side_turn


## allow_friendly：玩家普攻/加强攻可选友方；对手 AI 默认 false。
static func attackable_cells(
	board: TacticalBoard,
	attacker: TacticalUnitInstance,
	allow_friendly: bool = false
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not can_basic_attack(attacker, attacker.faction):
		return out
	for u in board.living_units():
		if u == attacker:
			continue
		if not allow_friendly and u.faction == attacker.faction:
			continue
		if GridMathScript.chebyshev(attacker.cell, u.cell) <= attacker.def.attack_range:
			out.append(u.cell)
	return out


static func try_basic_attack(
	board: TacticalBoard,
	attacker: TacticalUnitInstance,
	target_cell: Vector2i,
	active_faction: TacticalFaction.Id,
	allow_friendly: bool = false,
	bonus_damage: int = 0
) -> Dictionary:
	var result := {"ok": false, "log": "", "damage": 0, "killed": false, "target": null}
	if not can_basic_attack(attacker, active_faction):
		result["log"] = "本段行动已攻击过或无法攻击"
		return result
	var target := board.unit_at(target_cell)
	if target == null or target == attacker:
		result["log"] = "需要其他单位为目标"
		return result
	if not allow_friendly and target.faction == attacker.faction:
		result["log"] = "需要敌方单位"
		return result
	if GridMathScript.chebyshev(attacker.cell, target.cell) > attacker.def.attack_range:
		result["log"] = "目标不在攻击范围内"
		return result
	var dmg := attacker.effective_attack() + maxi(0, bonus_damage)
	var hurt := board.apply_damage(target, dmg, attacker)
	result["target"] = target
	result["damage"] = dmg
	result["killed"] = hurt.get("killed", false)
	# 仅对手 AI 记「本段已攻」；玩家次数完全由攻击卡驱动。
	if attacker.faction != TacticalFaction.Id.PLAYER:
		attacker.attacked_this_side_turn = true
	result["ok"] = hurt.get("ok", false)
	var extra: String = hurt.get("log", "")
	var tag := "加强攻" if bonus_damage > 0 else "普攻"
	result["log"] = "%s %s %s，造成 %d 伤害" % [
		attacker.def.display_name,
		tag,
		target.def.display_name,
		dmg,
	]
	if extra != "":
		result["log"] += " · " + extra
	if result["killed"]:
		result["log"] += "（击杀）"
	return result


static func faction_defeated(board: TacticalBoard, faction: TacticalFaction.Id) -> bool:
	for u in board.units:
		if u.faction == faction and u.is_alive():
			return false
	return true
