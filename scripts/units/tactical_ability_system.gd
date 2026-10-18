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
			return _apply_self_atk(board, unit, ab.self_atk_on_kill, "猎杀")
		TacticalActiveAbility.TriggerKind.ON_SIDE_TURN_START:
			return _apply_ally_buff(board, unit, ab)
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


static func _apply_ally_buff(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	ab: TacticalActiveAbility
) -> Array[String]:
	if ab.ally_atk_buff == 0:
		return []
	var allies := board.allies_in_radius(
		unit.cell, unit.faction, ab.ally_buff_radius, Vector2i(-999, -999)
	)
	var buffed := 0
	for ally in allies:
		if ally == unit:
			continue
		ally.atk_bonus += ab.ally_atk_buff
		buffed += 1
	if buffed == 0:
		return []
	board.changed.emit()
	return [
		"%s 鸣鼓：%d 名友军攻击+%d（本场）"
		% [unit.def.display_name, buffed, ab.ally_atk_buff],
	]
