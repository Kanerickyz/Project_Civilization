class_name TacticalAbilitySystem
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

## 释放主动技：每单位每「方行动段」最多一次；不替代 TurnClock.end_turn。


static func can_cast(caster: TacticalUnitInstance, active_faction: TacticalFaction.Id) -> bool:
	if caster == null or not caster.is_alive():
		return false
	if caster.faction != active_faction:
		return false
	if caster.skill_used_this_side_turn:
		return false
	return caster.def.active_ability != null


static func valid_target_cells(
	board: TacticalBoard,
	caster: TacticalUnitInstance,
	active_faction: TacticalFaction.Id
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ab := caster.def.active_ability
	if ab == null:
		return out
	match ab.target_kind:
		TacticalActiveAbility.TargetKind.ENEMY_UNIT:
			for u in board.living_units():
				if u.faction == caster.faction:
					continue
				if GridMathScript.chebyshev(caster.cell, u.cell) <= ab.range_chebyshev:
					out.append(u.cell)
		TacticalActiveAbility.TargetKind.SELF_CENTER_ALLIES:
			out.append(caster.cell)
	return out


static func cast(
	board: TacticalBoard,
	caster: TacticalUnitInstance,
	target_cell: Vector2i,
	active_faction: TacticalFaction.Id
) -> Dictionary:
	var result := {"ok": false, "log": ""}
	if not can_cast(caster, active_faction):
		result["log"] = "本段行动已用过技能或无法释放"
		return result
	var ab := caster.def.active_ability
	if ab == null:
		result["log"] = "无主动技"
		return result
	var valid := valid_target_cells(board, caster, active_faction)
	if target_cell not in valid:
		result["log"] = "目标不在范围内"
		return result

	match ab.target_kind:
		TacticalActiveAbility.TargetKind.ENEMY_UNIT:
			var target := board.unit_at(target_cell)
			if target == null or target.faction == caster.faction:
				result["log"] = "需要敌方单位"
				return result
			var dmg := caster.effective_attack() + ab.damage_add
			target.hp -= dmg
			var killed := not target.is_alive()
			if ab.self_atk_on_cast != 0:
				caster.atk_bonus += ab.self_atk_on_cast
			if killed and ab.self_atk_on_kill != 0:
				caster.atk_bonus += ab.self_atk_on_kill
			result["ok"] = true
			result["log"] = "%s 对 %s 造成 %d 伤害" % [
				caster.def.display_name,
				target.def.display_name,
				dmg,
			]
			if killed:
				result["log"] += "（击杀）"
		TacticalActiveAbility.TargetKind.SELF_CENTER_ALLIES:
			var allies := board.allies_in_radius(
				caster.cell, caster.faction, ab.ally_buff_radius, Vector2i(-999, -999)
			)
			var buffed := 0
			for ally in allies:
				if ally == caster:
					continue
				ally.atk_bonus += ab.ally_atk_buff
				buffed += 1
			if ab.self_atk_on_cast != 0:
				caster.atk_bonus += ab.self_atk_on_cast
			result["ok"] = true
			result["log"] = "%s 鸣鼓，%d 名友军攻击+%d" % [
				caster.def.display_name,
				buffed,
				ab.ally_atk_buff,
			]
		_:
			result["log"] = "未知技能类型"
			return result

	caster.skill_used_this_side_turn = true
	board.changed.emit()
	return result
