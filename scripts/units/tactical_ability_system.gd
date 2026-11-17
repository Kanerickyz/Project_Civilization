class_name TacticalAbilitySystem
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

## 时机触发战术能力；不替代 TurnClock.end_turn，无玩家点按释放。


static func process_battle_start(board: TacticalBoard) -> Array[String]:
	var logs: Array[String] = []
	for u in board.living_units():
		logs.append_array(_try_trigger(board, u, TacticalActiveAbility.TriggerKind.ON_SELF_DEPLOY))
	return logs


static func process_side_turn_start(board: TacticalBoard, faction: TacticalFaction.Id) -> Array[String]:
	var logs: Array[String] = []
	for u in board.living_units():
		if u.faction != faction:
			continue
		logs.append_array(
			_try_trigger(board, u, TacticalActiveAbility.TriggerKind.ON_SIDE_TURN_START)
		)
	return logs


static func process_unit_hurt(board: TacticalBoard, unit: TacticalUnitInstance, _damage: int) -> Array[String]:
	if unit == null or not unit.is_alive():
		return []
	return _try_trigger(board, unit, TacticalActiveAbility.TriggerKind.ON_SELF_HURT)


static func process_unit_kill(
	board: TacticalBoard,
	killer: TacticalUnitInstance,
	_victim: TacticalUnitInstance
) -> Array[String]:
	if killer == null or not killer.is_alive():
		return []
	return _try_trigger(board, killer, TacticalActiveAbility.TriggerKind.ON_SELF_KILL)


static func process_unit_move_end(board: TacticalBoard, unit: TacticalUnitInstance) -> Array[String]:
	if unit == null or not unit.is_alive():
		return []
	return _try_trigger(board, unit, TacticalActiveAbility.TriggerKind.ON_SELF_MOVE_END)


## 单位刚阵亡时触发（仍可读 cell / def）；用于爆爆死亡点燃等。
static func process_unit_death(board: TacticalBoard, unit: TacticalUnitInstance) -> Array[String]:
	if unit == null or unit.def == null:
		return []
	return _try_trigger(board, unit, TacticalActiveAbility.TriggerKind.ON_SELF_DEATH)


static func _try_trigger(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	kind: TacticalActiveAbility.TriggerKind
) -> Array[String]:
	var ab := unit.def.triggered_ability
	if ab == null or ab.trigger_kind != kind:
		return []
	match kind:
		TacticalActiveAbility.TriggerKind.ON_SELF_DEPLOY:
			if unit.deploy_trigger_fired:
				return []
			unit.deploy_trigger_fired = true
			return _apply_self_atk(board, unit, ab.self_atk_on_trigger, "入阵")
		TacticalActiveAbility.TriggerKind.ON_SELF_HURT:
			return _apply_self_atk(board, unit, ab.self_atk_on_trigger, "铁壁")
		TacticalActiveAbility.TriggerKind.ON_SELF_KILL:
			return _apply_kill_effects(board, unit, ab)
		TacticalActiveAbility.TriggerKind.ON_SIDE_TURN_START:
			return _apply_ally_buff(board, unit, ab, "鸣鼓")
		TacticalActiveAbility.TriggerKind.ON_SELF_MOVE_END:
			return _apply_ally_buff(board, unit, ab, "鼓阵")
		TacticalActiveAbility.TriggerKind.ON_SELF_DEATH:
			return _apply_death_aoe_burn(board, unit, ab)
		_:
			return []


static func _apply_self_atk(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	amount: int,
	tag: String
) -> Array[String]:
	if amount == 0:
		return []
	unit.atk_bonus += amount
	board.changed.emit()
	return [
		"%s %s：攻击+%d（本场）" % [unit.def.display_name, tag, amount],
	]


static func _apply_kill_effects(
	board: TacticalBoard,
	killer: TacticalUnitInstance,
	ab: TacticalActiveAbility
) -> Array[String]:
	var logs: Array[String] = []
	logs.append_array(_apply_self_atk(board, killer, ab.self_atk_on_kill, "猎杀"))
	if ab.grant_ephemeral_attack_on_kill:
		logs.append_array(_grant_ephemeral_attack(board, killer))
	return logs


static func _grant_ephemeral_attack(board: TacticalBoard, killer: TacticalUnitInstance) -> Array[String]:
	if killer.faction != TacticalFactionScript.Id.PLAYER:
		return []
	if board.player_deck == null:
		return []
	board.player_deck.add_ephemeral_attack_to_hand()
	return ["%s 猎获：手牌+1 临时攻击卡（用完销毁）" % killer.def.display_name]


static func _apply_ally_buff(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	ab: TacticalActiveAbility,
	tag: String
) -> Array[String]:
	if ab.ally_atk_buff == 0 and ab.ally_hp_buff == 0:
		return []
	var allies := board.allies_in_radius(
		unit.cell, unit.faction, ab.ally_buff_radius, Vector2i(-999, -999)
	)
	var buffed := 0
	for ally in allies:
		if ally == unit:
			continue
		if ab.ally_atk_buff != 0:
			ally.atk_bonus += ab.ally_atk_buff
		if ab.ally_hp_buff != 0:
			ally.max_hp_bonus += ab.ally_hp_buff
			ally.hp += ab.ally_hp_buff
		buffed += 1
	if buffed == 0:
		return []
	board.changed.emit()
	var parts: PackedStringArray = []
	if ab.ally_atk_buff != 0:
		parts.append("攻击+%d" % ab.ally_atk_buff)
	if ab.ally_hp_buff != 0:
		parts.append("生命+%d" % ab.ally_hp_buff)
	return [
		"%s %s：%d 名周围角色 %s（本场）"
		% [unit.def.display_name, tag, buffed, "、".join(parts)],
	]


static func _apply_death_aoe_burn(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	ab: TacticalActiveAbility
) -> Array[String]:
	if ab.aoe_burn_stacks <= 0:
		return []
	var n := board.apply_burn_aoe(unit.cell, ab.aoe_burn_stacks, ab.aoe_burn_radius, null)
	if n <= 0:
		return [
			"%s 爆燃：周围无单位可点燃" % unit.def.display_name,
		]
	return [
		"%s 爆燃：%d 名单位获得 %d 层燃烧"
		% [unit.def.display_name, n, ab.aoe_burn_stacks],
	]
