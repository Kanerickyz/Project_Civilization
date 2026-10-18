class_name TacticalCombat
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")

## 普攻与伤害；不替代主动技系统。


static func can_basic_attack(attacker: TacticalUnitInstance, active_faction: TacticalFaction.Id) -> bool:
	if attacker == null or not attacker.is_alive():
		return false
	if attacker.faction != active_faction:
		return false
	return not attacker.attacked_this_side_turn


static func attackable_cells(
	board: TacticalBoard, attacker: TacticalUnitInstance
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not can_basic_attack(attacker, attacker.faction):
		return out
	for u in board.living_units():
		if u.faction == attacker.faction:
			continue
		if GridMathScript.chebyshev(attacker.cell, u.cell) <= attacker.def.attack_range:
			out.append(u.cell)
	return out


static func try_basic_attack(
	board: TacticalBoard,
	attacker: TacticalUnitInstance,
	target_cell: Vector2i,
	active_faction: TacticalFaction.Id
) -> Dictionary:
	var result := {"ok": false, "log": "", "damage": 0, "killed": false}
	if not can_basic_attack(attacker, active_faction):
		result["log"] = "本段行动已攻击过或无法攻击"
		return result
	var target := board.unit_at(target_cell)
	if target == null or target.faction == attacker.faction:
		result["log"] = "需要敌方单位"
		return result
	if GridMathScript.chebyshev(attacker.cell, target.cell) > attacker.def.attack_range:
		result["log"] = "目标不在攻击范围内"
		return result
	var dmg := attacker.effective_attack()
	var hurt := board.apply_damage(target, dmg, attacker)
	result["damage"] = dmg
	result["killed"] = hurt.get("killed", false)
	attacker.attacked_this_side_turn = true
	result["ok"] = hurt.get("ok", false)
	var extra: String = hurt.get("log", "")
	result["log"] = "%s 普攻 %s，造成 %d 伤害" % [
		attacker.def.display_name,
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
