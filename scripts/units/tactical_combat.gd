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
		# 敌方不可选隐身目标；友方/己方仍可选。
		if u.is_stealthed() and u.faction != attacker.faction:
			continue
		var dist := GridMathScript.chebyshev(attacker.cell, u.cell)
		if not attacker.def.is_chebyshev_in_attack_band(dist):
			continue
		if not board.has_attack_los(attacker.cell, u.cell):
			continue
		out.append(u.cell)
	return out


## 盾卫击退：落点不可走时最终伤害 ×1.2 向上取整。
const KNIGHT_KNOCKBACK_BLOCK_MULT := 1.2
## 盾卫击退撞到落点单位时的额外伤害。
const KNIGHT_KNOCKBACK_COLLISION_DAMAGE := 1


## 攻击方向单位步（切比雪夫邻格）；同格返回 (0,0)。
static func attack_direction_step(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	return Vector2i(signi(to_cell.x - from_cell.x), signi(to_cell.y - from_cell.y))


static func try_basic_attack(
	board: TacticalBoard,
	attacker: TacticalUnitInstance,
	target_cell: Vector2i,
	active_faction: TacticalFaction.Id,
	allow_friendly: bool = false,
	bonus_damage: int = 0,
	aoe_burn_stacks: int = 0
) -> Dictionary:
	var result := {
		"ok": false,
		"log": "",
		"damage": 0,
		"killed": false,
		"target": null,
		"burn_applied": 0,
		"knockback_from": Vector2i(-1, -1),
		"knockback_to": Vector2i(-1, -1),
		"knockback_moved": false,
		"knockback_blocked": false,
		"collision_target": null,
		"collision_damage": 0,
		"collision_killed": false,
	}
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
	if target.is_stealthed() and target.faction != attacker.faction:
		result["log"] = "目标隐身不可选"
		return result
	var dist := GridMathScript.chebyshev(attacker.cell, target.cell)
	if not attacker.def.is_chebyshev_in_attack_band(dist):
		result["log"] = "目标不在攻击范围内"
		return result
	if not board.has_attack_los(attacker.cell, target.cell):
		result["log"] = "树林挡住攻击"
		return result
	# 攻击取消自身隐身。
	attacker.break_stealth()
	# 狂暴倍率作用于基础攻+加强额外，再向上取整。
	var dmg := attacker.apply_frenzy_to_damage(attacker.attack_power() + maxi(0, bonus_damage))
	var from_cell := target.cell
	var is_knight := attacker.def != null and attacker.def.id == "knight"
	var step := attack_direction_step(attacker.cell, target.cell)
	var knock_to := from_cell + step
	var knock_blocked := false
	var occupant: TacticalUnitInstance = null
	if is_knight and step != Vector2i.ZERO:
		result["knockback_from"] = from_cell
		result["knockback_to"] = knock_to
		occupant = board.unit_at(knock_to)
		# 不可走：地图外/树林等，或落点已有单位（含友方）。
		knock_blocked = (not board.is_passable(knock_to)) or (occupant != null)
		result["knockback_blocked"] = knock_blocked
		if knock_blocked:
			# 最终伤害 ×1.2 向上取整，替代本次普通伤害。
			dmg = int(ceili(float(dmg) * KNIGHT_KNOCKBACK_BLOCK_MULT))
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
	if aoe_burn_stacks > 0:
		tag = "燃爆攻"
	result["log"] = "%s %s %s，造成 %d 伤害" % [
		attacker.def.display_name,
		tag,
		target.def.display_name,
		dmg,
	]
	if is_knight and step != Vector2i.ZERO and knock_blocked:
		result["log"] += " · 击退受阻×1.2"
	if extra != "":
		result["log"] += " · " + extra
	if result["killed"]:
		result["log"] += "（击杀）"
	# 落点有其他单位：额外 1 点伤害（可为友方）。
	if is_knight and knock_blocked and occupant != null and occupant != target and occupant.is_alive():
		var col := board.apply_damage(occupant, KNIGHT_KNOCKBACK_COLLISION_DAMAGE, attacker)
		result["collision_target"] = occupant
		result["collision_damage"] = KNIGHT_KNOCKBACK_COLLISION_DAMAGE
		result["collision_killed"] = col.get("killed", false)
		result["log"] += " · 撞到 %s +%d" % [
			occupant.def.display_name,
			KNIGHT_KNOCKBACK_COLLISION_DAMAGE,
		]
		if result["collision_killed"]:
			result["log"] += "（击杀）"
	# 可退后且目标仍存活：位移 1 格（不触发移动结束被动；表现靠视图 Tween）。
	if is_knight and step != Vector2i.ZERO and not knock_blocked and target.is_alive():
		if board.force_displace(target, knock_to):
			result["knockback_moved"] = true
			result["log"] += " · 击退至 (%d,%d)" % [knock_to.x, knock_to.y]
	# 技能燃爆：对目标格及周围施加燃烧（排除攻击者）。目标已死仍对周围生效。
	# 击退后仍按原目标格做燃爆 AoE（盾卫无燃爆；其它单位不受影响）。
	if result["ok"] and aoe_burn_stacks > 0:
		var burned := board.apply_burn_aoe(target_cell, aoe_burn_stacks, 1, attacker)
		result["burn_applied"] = burned
		if burned > 0:
			result["log"] += " · 燃爆：%d 名单位 +%d 燃烧" % [burned, aoe_burn_stacks]
	return result


static func faction_defeated(board: TacticalBoard, faction: TacticalFaction.Id) -> bool:
	for u in board.units:
		if u.faction == faction and u.is_alive():
			return false
	return true
