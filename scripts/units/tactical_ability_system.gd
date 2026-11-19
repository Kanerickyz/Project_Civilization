class_name TacticalAbilitySystem
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")

## 时机触发战术能力；不替代 TurnClock.end_turn，无玩家点按释放。
## 可选 fx_out：追加 Dictionary 飘字事件 {cell, text, color}，供沙盘可见反馈。
## 受益格飘数值；触发者本体另飘短能力名（小丑牌式弹出/晃动由沙盘播）。


static func process_battle_start(board: TacticalBoard, fx_out: Variant = null) -> Array[String]:
	var logs: Array[String] = []
	for u in board.living_units():
		logs.append_array(
			_try_trigger(board, u, TacticalActiveAbility.TriggerKind.ON_SELF_DEPLOY, fx_out)
		)
	return logs


static func process_side_turn_start(
	board: TacticalBoard, faction: TacticalFaction.Id, fx_out: Variant = null
) -> Array[String]:
	var logs: Array[String] = []
	for u in board.living_units():
		if u.faction != faction:
			continue
		logs.append_array(
			_try_trigger(board, u, TacticalActiveAbility.TriggerKind.ON_SIDE_TURN_START, fx_out)
		)
	return logs


static func process_unit_hurt(
	board: TacticalBoard, unit: TacticalUnitInstance, _damage: int, fx_out: Variant = null
) -> Array[String]:
	if unit == null or not unit.is_alive():
		return []
	return _try_trigger(board, unit, TacticalActiveAbility.TriggerKind.ON_SELF_HURT, fx_out)


static func process_unit_kill(
	board: TacticalBoard,
	killer: TacticalUnitInstance,
	_victim: TacticalUnitInstance,
	fx_out: Variant = null
) -> Array[String]:
	if killer == null or not killer.is_alive():
		return []
	return _try_trigger(board, killer, TacticalActiveAbility.TriggerKind.ON_SELF_KILL, fx_out)


static func process_unit_move_end(
	board: TacticalBoard, unit: TacticalUnitInstance, fx_out: Variant = null
) -> Array[String]:
	if unit == null or not unit.is_alive():
		return []
	return _try_trigger(board, unit, TacticalActiveAbility.TriggerKind.ON_SELF_MOVE_END, fx_out)


## 单位刚阵亡时触发（仍可读 cell / def）；用于爆爆死亡点燃等。
static func process_unit_death(
	board: TacticalBoard, unit: TacticalUnitInstance, fx_out: Variant = null
) -> Array[String]:
	if unit == null or unit.def == null:
		return []
	return _try_trigger(board, unit, TacticalActiveAbility.TriggerKind.ON_SELF_DEATH, fx_out)


## 同阵营其他单位阵亡后：扫描仍存活友方的 ON_ALLY_DEATH 被动（不含死者自身）。
static func process_ally_death(
	board: TacticalBoard, dead: TacticalUnitInstance, fx_out: Variant = null
) -> Array[String]:
	if board == null or dead == null:
		return []
	var logs: Array[String] = []
	for u in board.living_units():
		if u == dead or u.faction != dead.faction:
			continue
		logs.append_array(
			_try_trigger(board, u, TacticalActiveAbility.TriggerKind.ON_ALLY_DEATH, fx_out)
		)
	return logs


## 玩家一张攻击瞄准卡选定有效目标并成功结算后：扫描存活己方单位的 ON_PLAYER_ATTACK_CARD 被动。
## 授权未出手、取消瞄准、无效/回手不触发。
static func process_player_attack_card_played(
	board: TacticalBoard, fx_out: Variant = null
) -> Array[String]:
	if board == null:
		return []
	var logs: Array[String] = []
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		logs.append_array(
			_try_trigger(board, u, TacticalActiveAbility.TriggerKind.ON_PLAYER_ATTACK_CARD, fx_out)
		)
	return logs


static func _emit_fx(fx_out: Variant, cell: Vector2i, text: String, color: Color) -> void:
	if text.is_empty() or not (fx_out is Array):
		return
	(fx_out as Array).append({"cell": cell, "text": text, "color": color})


static func _try_trigger(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	kind: TacticalActiveAbility.TriggerKind,
	fx_out: Variant = null
) -> Array[String]:
	var ab := unit.def.triggered_ability
	if ab == null or ab.trigger_kind != kind:
		return []
	match kind:
		TacticalActiveAbility.TriggerKind.ON_SELF_DEPLOY:
			if unit.deploy_trigger_fired:
				return []
			unit.deploy_trigger_fired = true
			return _apply_self_atk(board, unit, ab.self_atk_on_trigger, "入阵", fx_out)
		TacticalActiveAbility.TriggerKind.ON_SELF_HURT:
			var hurt_logs: Array[String] = []
			hurt_logs.append_array(
				_apply_self_atk(board, unit, ab.self_atk_on_trigger, "铁壁", fx_out)
			)
			hurt_logs.append_array(_apply_ally_heal_on_hurt(board, unit, ab, fx_out))
			return hurt_logs
		TacticalActiveAbility.TriggerKind.ON_SELF_KILL:
			return _apply_kill_effects(board, unit, ab, fx_out)
		TacticalActiveAbility.TriggerKind.ON_SIDE_TURN_START:
			return _apply_ally_buff(board, unit, ab, "鸣鼓", fx_out)
		TacticalActiveAbility.TriggerKind.ON_SELF_MOVE_END:
			return _apply_ally_buff(board, unit, ab, "鼓阵", fx_out)
		TacticalActiveAbility.TriggerKind.ON_SELF_DEATH:
			return _apply_death_aoe_burn(board, unit, ab)
		TacticalActiveAbility.TriggerKind.ON_PLAYER_ATTACK_CARD:
			return _apply_player_attack_card(board, unit, ab, fx_out)
		TacticalActiveAbility.TriggerKind.ON_ALLY_DEATH:
			return _draw_cards_on_trigger(board, unit, ab, fx_out)
		_:
			return []


static func _apply_player_attack_card(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	ab: TacticalActiveAbility,
	fx_out: Variant = null
) -> Array[String]:
	var logs: Array[String] = []
	logs.append_array(
		_apply_ally_buff(
			board,
			unit,
			ab,
			ab.display_name if not ab.display_name.is_empty() else "战鼓",
			fx_out
		)
	)
	logs.append_array(_draw_cards_on_trigger(board, unit, ab, fx_out))
	return logs


static func _draw_cards_on_trigger(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	ab: TacticalActiveAbility,
	fx_out: Variant = null
) -> Array[String]:
	var n := ab.draw_cards_on_trigger
	if n <= 0:
		return []
	if board.player_deck == null:
		return []
	var drawn := board.player_deck.draw_up_to(n)
	var tag := ab.display_name if not ab.display_name.is_empty() else "抽牌"
	if drawn <= 0:
		return ["%s %s：牌库无可抽" % [unit.def.display_name, tag]]
	_emit_fx(fx_out, unit.cell, "+%d牌" % drawn, Color("7ec8ff"))
	return ["%s %s：抽 %d 张" % [unit.def.display_name, tag, drawn]]


static func _apply_self_atk(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	amount: int,
	tag: String,
	fx_out: Variant = null
) -> Array[String]:
	if amount == 0:
		return []
	unit.atk_bonus += amount
	board.changed.emit()
	_emit_fx(fx_out, unit.cell, "+%d攻" % amount, Color("ffe08a"))
	return [
		"%s %s：攻击+%d（本场）" % [unit.def.display_name, tag, amount],
	]


## 受击被动：周围友方恢复当前 HP（排除自身；不抬上限）。
static func _apply_ally_heal_on_hurt(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	ab: TacticalActiveAbility,
	fx_out: Variant = null
) -> Array[String]:
	var amount := ab.ally_heal_on_trigger
	if amount <= 0:
		return []
	var radius := ab.ally_buff_radius if ab.ally_buff_radius > 0 else ab.range_chebyshev
	if radius < 0:
		radius = 1
	var allies := board.allies_in_radius(unit.cell, unit.faction, radius, unit.cell)
	var healed := 0
	for ally in allies:
		if ally == unit:
			continue
		var gained := ally.apply_heal(amount)
		if gained <= 0:
			continue
		healed += 1
		_emit_fx(fx_out, ally.cell, "+%d血" % gained, Color("7dff9a"))
	if healed == 0:
		return []
	board.changed.emit()
	var tag := ab.display_name if not ab.display_name.is_empty() else "共情"
	# 触发者本体短标签，供单位晃动/弹出对齐（数值仍在受益友方格；非金色）。
	_emit_fx(fx_out, unit.cell, tag, Color("f5f5f5"))
	return [
		"%s %s：%d 名周围友方恢复 %d 血" % [unit.def.display_name, tag, healed, amount],
	]


static func _apply_kill_effects(
	board: TacticalBoard,
	killer: TacticalUnitInstance,
	ab: TacticalActiveAbility,
	fx_out: Variant = null
) -> Array[String]:
	var logs: Array[String] = []
	logs.append_array(_apply_self_atk(board, killer, ab.self_atk_on_kill, "猎杀", fx_out))
	if ab.grant_ephemeral_attack_on_kill:
		logs.append_array(_grant_ephemeral_attack(board, killer, fx_out))
	if ab.ally_attack_on_kill:
		logs.append_array(_apply_ally_attack_on_kill(board, killer, ab, fx_out))
	return logs


static func _grant_ephemeral_attack(
	board: TacticalBoard, killer: TacticalUnitInstance, fx_out: Variant = null
) -> Array[String]:
	if killer.faction != TacticalFactionScript.Id.PLAYER:
		return []
	if board.player_deck == null:
		return []
	board.player_deck.add_ephemeral_attack_to_hand()
	_emit_fx(fx_out, killer.cell, "+1临攻", Color("7ec8ff"))
	return ["%s 猎获：手牌+1 临时攻击卡（用完销毁）" % killer.def.display_name]


## 击杀被动：周围友方各尝试普攻一次；无合法敌则跳过；用友军自身攻距/攻。
static func _apply_ally_attack_on_kill(
	board: TacticalBoard,
	killer: TacticalUnitInstance,
	ab: TacticalActiveAbility,
	fx_out: Variant = null
) -> Array[String]:
	if board == null or killer == null or not killer.is_alive():
		return []
	var radius := ab.ally_buff_radius if ab.ally_buff_radius > 0 else ab.range_chebyshev
	if radius < 0:
		radius = 1
	var allies := board.allies_in_radius(killer.cell, killer.faction, radius, killer.cell)
	var tag := ab.display_name if not ab.display_name.is_empty() else "猎召"
	var fired := 0
	var hit_logs: PackedStringArray = []
	for ally in allies:
		if ally == null or ally == killer or not ally.is_alive():
			continue
		if ally.effective_attack() <= 0:
			continue
		var cells: Array[Vector2i] = TacticalCombatScript.attackable_cells(board, ally, false)
		if cells.is_empty():
			continue
		var target_cell := _pick_nearest_enemy_cell(board, ally, cells)
		if target_cell.x < -900:
			continue
		var atk: Dictionary = TacticalCombatScript.try_basic_attack(
			board, ally, target_cell, ally.faction, false
		)
		if not bool(atk.get("ok", false)):
			continue
		fired += 1
		_emit_fx(fx_out, ally.cell, tag, Color("ffe08a"))
		# 嵌套伤害/击杀被动飘字并入本次击杀反馈。
		var nested_fx: Array = atk.get("passive_fx", []) as Array
		if fx_out is Array and not nested_fx.is_empty():
			(fx_out as Array).append_array(nested_fx)
		var victim: TacticalUnitInstance = atk.get("target") as TacticalUnitInstance
		var vname := victim.def.display_name if victim != null and victim.def != null else "?"
		hit_logs.append(
			"%s→%s %d%s"
			% [
				ally.def.display_name,
				vname,
				int(atk.get("damage", 0)),
				"（击杀）" if bool(atk.get("killed", false)) else "",
			]
		)
	if fired == 0:
		return []
	board.changed.emit()
	return [
		"%s %s：%d 名周围友方出击（%s）"
		% [killer.def.display_name, tag, fired, "、".join(hit_logs)],
	]


static func _pick_nearest_enemy_cell(
	board: TacticalBoard, attacker: TacticalUnitInstance, cells: Array[Vector2i]
) -> Vector2i:
	var best := Vector2i(-999, -999)
	var best_dist := 999999
	var best_hp := 999999
	for c in cells:
		var t := board.unit_at(c)
		if t == null or not t.is_alive() or t.faction == attacker.faction:
			continue
		var d := GridMathScript.chebyshev(attacker.cell, c)
		if d < best_dist or (d == best_dist and t.hp < best_hp):
			best_dist = d
			best_hp = t.hp
			best = c
	return best


static func _apply_ally_buff(
	board: TacticalBoard,
	unit: TacticalUnitInstance,
	ab: TacticalActiveAbility,
	tag: String,
	fx_out: Variant = null
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
		# 每名受益友方：加攻/加血各一条飘字事件（同格由视图队列逐个弹）。
		if ab.ally_atk_buff != 0:
			_emit_fx(fx_out, ally.cell, "+%d攻" % ab.ally_atk_buff, Color("ffe08a"))
		if ab.ally_hp_buff != 0:
			_emit_fx(fx_out, ally.cell, "+%d血" % ab.ally_hp_buff, Color("7dff9a"))
	if buffed == 0:
		return []
	board.changed.emit()
	var label := ab.display_name if not ab.display_name.is_empty() else tag
	_emit_fx(fx_out, unit.cell, label, Color("f5f5f5"))
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
