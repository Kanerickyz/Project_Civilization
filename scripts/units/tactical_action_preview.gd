class_name TacticalActionPreview
extends RefCounted
## 只读预览：快照→试算→还原，供拖牌/瞄准展示伤害与触发链路。
## 不改写牌库语义；试算时暂时 mute board.changed，并还原单位与三库。


const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")


static func preview_basic_attack(
	board: TacticalBoard,
	attacker: TacticalUnitInstance,
	target_cell: Vector2i,
	bonus_damage: int = 0,
	aoe_burn_stacks: int = 0,
	volley: bool = false,
	include_attack_card_passive: bool = true
) -> Dictionary:
	var empty := _empty_preview("无效攻击预览")
	if board == null or attacker == null:
		return empty
	var snap := _snapshot(board)
	board.begin_preview_mute()
	var atk := TacticalCombatScript.try_basic_attack(
		board,
		attacker,
		target_cell,
		TacticalFactionScript.Id.PLAYER,
		true,
		bonus_damage,
		aoe_burn_stacks,
		volley
	)
	var steps: Array = []
	var unit_deltas: Dictionary = {}
	if bool(atk.get("ok", false)):
		_collect_attack_steps(atk, steps)
		if include_attack_card_passive:
			var card_fx: Array = []
			var card_logs := TacticalAbilitySystemScript.process_player_attack_card_played(
				board, card_fx
			)
			for lg in card_logs:
				steps.append({"text": str(lg), "kind": "trigger"})
			_append_fx_steps(card_fx, steps)
		unit_deltas = _unit_deltas_from_snap(board, snap)
	_restore(board, snap)
	board.end_preview_mute()
	if not bool(atk.get("ok", false)):
		return _empty_preview(str(atk.get("log", "无法攻击")))
	return {
		"ok": true,
		"log": str(atk.get("log", "")),
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": unit_deltas,
		"hover_cell": target_cell,
	}


static func preview_charge(
	board: TacticalBoard, knight: TacticalUnitInstance, dir_cell: Vector2i
) -> Dictionary:
	if board == null or knight == null:
		return _empty_preview("无效冲撞预览")
	var snap := _snapshot(board)
	board.begin_preview_mute()
	var res := TacticalCombatScript.try_knight_charge(board, knight, dir_cell)
	var steps: Array = []
	var unit_deltas: Dictionary = {}
	if bool(res.get("ok", false)):
		_collect_charge_steps(res, steps)
		_append_fx_steps(res.get("passive_fx", []) as Array, steps)
		unit_deltas = _unit_deltas_from_snap(board, snap)
	_restore(board, snap)
	board.end_preview_mute()
	if not bool(res.get("ok", false)):
		return _empty_preview(str(res.get("log", "无法冲撞")))
	return {
		"ok": true,
		"log": str(res.get("log", "")),
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": unit_deltas,
		"hover_cell": dir_cell,
	}


static func preview_heal_potion(
	board: TacticalBoard, caster: TacticalUnitInstance, cell: Vector2i
) -> Dictionary:
	if board == null or caster == null:
		return _empty_preview("无效恢复预览")
	var snap := _snapshot(board)
	board.begin_preview_mute()
	var res := board.apply_heal_potion(caster, cell, 2, 1)
	var steps: Array = []
	var unit_deltas: Dictionary = {}
	if bool(res.get("ok", false)):
		for h in res.get("healed", []) as Array:
			if not (h is Dictionary):
				continue
			var u: TacticalUnitInstance = (h as Dictionary).get("unit") as TacticalUnitInstance
			var amt := int((h as Dictionary).get("amount", 0))
			if u == null or amt <= 0:
				continue
			steps.append(
				{
					"text": "+%d血" % amt,
					"kind": "heal",
					"cell": u.cell,
					"unit": u,
				}
			)
		_append_fx_steps(res.get("passive_fx", []) as Array, steps)
		unit_deltas = _unit_deltas_from_snap(board, snap)
	_restore(board, snap)
	board.end_preview_mute()
	if not bool(res.get("ok", false)):
		return _empty_preview(str(res.get("log", "无法恢复")))
	if steps.is_empty():
		steps.append({"text": "无友方可回血", "kind": "info"})
	return {
		"ok": true,
		"log": str(res.get("log", "")),
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": unit_deltas,
		"hover_cell": cell,
	}


static func preview_inspire(board: TacticalBoard, drummer: TacticalUnitInstance) -> Dictionary:
	if board == null or drummer == null:
		return _empty_preview("无效鼓舞预览")
	var snap := _snapshot(board)
	board.begin_preview_mute()
	var res := board.apply_inspire_frenzy(drummer, 1)
	var steps: Array = []
	var unit_deltas: Dictionary = {}
	if bool(res.get("ok", false)):
		_append_fx_steps(res.get("passive_fx", []) as Array, steps)
		if steps.is_empty():
			steps.append({"text": "周围无友方", "kind": "info"})
		unit_deltas = _unit_deltas_from_snap(board, snap)
	_restore(board, snap)
	board.end_preview_mute()
	if not bool(res.get("ok", false)):
		return _empty_preview(str(res.get("log", "无法鼓舞")))
	return {
		"ok": true,
		"log": str(res.get("log", "")),
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": unit_deltas,
		"hover_cell": drummer.cell,
	}


static func preview_armor(target: TacticalUnitInstance, amount: int) -> Dictionary:
	if target == null or not target.is_alive():
		return _empty_preview("无效护甲预览")
	var grant := maxi(1, amount)
	var after_armor := target.armor + grant
	var steps: Array = [
		{"text": "+%d甲" % grant, "kind": "buff", "cell": target.cell, "unit": target}
	]
	var deltas := {
		target: {
			"hp": target.hp,
			"max_hp": target.effective_max_hp(),
			"armor": after_armor,
			"hp_delta": 0,
			"armor_delta": grant,
		}
	}
	return {
		"ok": true,
		"log": "%s +%d 护甲" % [target.def.display_name, grant],
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": deltas,
		"hover_cell": target.cell,
	}


static func preview_move_authorize(unit: TacticalUnitInstance) -> Dictionary:
	if unit == null or not unit.is_alive() or unit.def == null:
		return _empty_preview("无效移动预览")
	var steps: Array = [
		{
			"text": "移力→%d" % unit.def.move_range,
			"kind": "move",
			"cell": unit.cell,
			"unit": unit,
		},
		{"text": "点绿格移动", "kind": "info"},
	]
	return {
		"ok": true,
		"log": "%s 获移动授权" % unit.def.display_name,
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": {},
		"hover_cell": unit.cell,
		"show_reachable": true,
		"move_unit": unit,
	}


static func preview_move_step(
	board: TacticalBoard, unit: TacticalUnitInstance, dest: Vector2i
) -> Dictionary:
	if board == null or unit == null or not unit.is_alive():
		return _empty_preview("无效落点")
	var reachable := board.reachable_move_cells(unit)
	if not (dest in reachable):
		return _empty_preview("不可达")
	var steps: Array = [
		{
			"text": "移至 (%d,%d)" % [dest.x, dest.y],
			"kind": "move",
			"cell": dest,
			"unit": unit,
		}
	]
	return {
		"ok": true,
		"log": "%s → (%d,%d)" % [unit.def.display_name, dest.x, dest.y],
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": {},
		"hover_cell": dest,
	}


static func preview_stealth(target: TacticalUnitInstance) -> Dictionary:
	if target == null or not target.is_alive():
		return _empty_preview("无效隐身预览")
	var steps: Array = [
		{"text": "隐身", "kind": "buff", "cell": target.cell, "unit": target}
	]
	return {
		"ok": true,
		"log": "%s 隐身" % target.def.display_name,
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": {},
		"hover_cell": target.cell,
	}


static func preview_skill_draw() -> Dictionary:
	var steps: Array = [
		{"text": "弃光手牌", "kind": "info"},
		{"text": "再抽5", "kind": "info"},
	]
	return {
		"ok": true,
		"log": "鸣鼓换手",
		"steps": steps,
		"chain_text": _join_steps(steps),
		"unit_deltas": {},
		"hover_cell": Vector2i(-1, -1),
	}


static func _empty_preview(log: String) -> Dictionary:
	return {
		"ok": false,
		"log": log,
		"steps": [],
		"chain_text": "",
		"unit_deltas": {},
		"hover_cell": Vector2i(-1, -1),
	}


static func _join_steps(steps: Array) -> String:
	var parts: PackedStringArray = []
	var seen: Dictionary = {}
	for s in steps:
		if not (s is Dictionary):
			continue
		var t := str((s as Dictionary).get("text", "")).strip_edges()
		if t.is_empty() or seen.has(t):
			continue
		seen[t] = true
		parts.append(t)
	return " → ".join(parts)


static func _append_fx_steps(fx: Array, steps: Array) -> void:
	for ev in fx:
		if not (ev is Dictionary):
			continue
		var text := str((ev as Dictionary).get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var kind := "trigger"
		var sync := str((ev as Dictionary).get("sync", ""))
		var fk := str((ev as Dictionary).get("kind", ""))
		if text.begins_with("+") and text.contains("血"):
			kind = "heal"
		elif text.begins_with("-") or text.begins_with("−"):
			kind = "damage"
		elif sync.begins_with("buff") or text.contains("攻") or text.contains("狂") or text.contains("甲"):
			kind = "buff"
		elif fk == "skill_prompt":
			kind = "trigger"
		steps.append(
			{
				"text": text,
				"kind": kind,
				"cell": (ev as Dictionary).get("cell", Vector2i(-1, -1)),
			}
		)


static func _collect_attack_steps(atk: Dictionary, steps: Array) -> void:
	var dmg := int(atk.get("damage", 0))
	var target: TacticalUnitInstance = atk.get("target") as TacticalUnitInstance
	if dmg > 0 and target != null:
		var armor_note := ""
		steps.append(
			{
				"text": "-%d" % dmg,
				"kind": "damage",
				"cell": target.cell,
				"unit": target,
				"extra": armor_note,
			}
		)
	if bool(atk.get("knockback_blocked", false)):
		steps.append({"text": "击退受阻×1.2", "kind": "info"})
	elif bool(atk.get("knockback_moved", false)):
		var kto: Vector2i = atk.get("knockback_to", Vector2i(-1, -1)) as Vector2i
		steps.append({"text": "击退(%d,%d)" % [kto.x, kto.y], "kind": "info"})
	if bool(atk.get("killed", false)):
		steps.append({"text": "击杀", "kind": "trigger"})
	var col: TacticalUnitInstance = atk.get("collision_target") as TacticalUnitInstance
	var col_dmg := int(atk.get("collision_damage", 0))
	if col != null and col_dmg > 0:
		steps.append(
			{"text": "撞-%d" % col_dmg, "kind": "damage", "cell": col.cell, "unit": col}
		)
		if bool(atk.get("collision_killed", false)):
			steps.append({"text": "撞杀", "kind": "trigger"})
	for hit in atk.get("volley_hits", []) as Array:
		if not (hit is Dictionary):
			continue
		var vu: TacticalUnitInstance = (hit as Dictionary).get("unit") as TacticalUnitInstance
		var vdmg := int((hit as Dictionary).get("damage", 0))
		if vu == null or vdmg <= 0:
			continue
		steps.append(
			{"text": "齐发-%d" % vdmg, "kind": "damage", "cell": vu.cell, "unit": vu}
		)
		if bool((hit as Dictionary).get("killed", false)):
			steps.append({"text": "齐发击杀", "kind": "trigger"})
	if int(atk.get("burn_applied", 0)) > 0:
		steps.append({"text": "燃爆+%d" % int(atk.get("burn_applied", 0)), "kind": "buff"})
	_append_fx_steps(atk.get("passive_fx", []) as Array, steps)


static func _collect_charge_steps(res: Dictionary, steps: Array) -> void:
	for hit in res.get("hits", []) as Array:
		if not (hit is Dictionary):
			continue
		var vu: TacticalUnitInstance = (hit as Dictionary).get("unit") as TacticalUnitInstance
		var vdmg := int((hit as Dictionary).get("damage", 0))
		if vu == null or vdmg <= 0:
			continue
		steps.append(
			{"text": "撞-%d" % vdmg, "kind": "damage", "cell": vu.cell, "unit": vu}
		)
		if bool((hit as Dictionary).get("killed", false)):
			steps.append({"text": "击杀", "kind": "trigger"})
		elif bool((hit as Dictionary).get("knock_moved", false)):
			steps.append({"text": "撞开", "kind": "info"})
	var self_dmg := int(res.get("self_damage", 0))
	if self_dmg > 0:
		steps.append({"text": "撞墙自伤-%d" % self_dmg, "kind": "damage"})
		if bool(res.get("self_killed", false)):
			steps.append({"text": "自灭", "kind": "trigger"})


static func _snapshot(board: TacticalBoard) -> Dictionary:
	var units_snap: Array = []
	for u in board.units:
		units_snap.append(
			{
				"unit": u,
				"cell": u.cell,
				"hp": u.hp,
				"atk_bonus": u.atk_bonus,
				"max_hp_bonus": u.max_hp_bonus,
				"moved_this_side_turn": u.moved_this_side_turn,
				"remaining_move_budget": u.remaining_move_budget,
				"attacked_this_side_turn": u.attacked_this_side_turn,
				"deploy_trigger_fired": u.deploy_trigger_fired,
				"burn_stacks": u.burn_stacks,
				"frenzy_stacks": u.frenzy_stacks,
				"armor": u.armor,
				"death_cards_culled": u.death_cards_culled,
				"next_intent": u.next_intent,
				"stealthed": u.stealthed,
			}
		)
	var deck_snap := {}
	var deck := board.player_deck
	if deck != null:
		deck_snap = {
			"hand": deck.hand.duplicate(),
			"draw_pile": deck.draw_pile.duplicate(),
			"discard_pile": deck.discard_pile.duplicate(),
			"move_authorized": deck.move_authorized.duplicate(),
			"attack_bonus_queues": deck.attack_bonus_queues.duplicate(true),
			"pending_attack_bonus": deck.pending_attack_bonus,
			"pending_aoe_burn_stacks": deck.pending_aoe_burn_stacks,
			"pending_volley": deck.pending_volley,
		}
	return {
		"units": units_snap,
		"ignited": board.ignited_aoe_cells_snapshot(),
		"deck": deck_snap,
	}


static func _restore(board: TacticalBoard, snap: Dictionary) -> void:
	for row_v in snap.get("units", []) as Array:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var u: TacticalUnitInstance = row.get("unit") as TacticalUnitInstance
		if u == null:
			continue
		u.cell = row.get("cell", u.cell) as Vector2i
		u.hp = int(row.get("hp", u.hp))
		u.atk_bonus = int(row.get("atk_bonus", u.atk_bonus))
		u.max_hp_bonus = int(row.get("max_hp_bonus", u.max_hp_bonus))
		u.moved_this_side_turn = bool(row.get("moved_this_side_turn", u.moved_this_side_turn))
		u.remaining_move_budget = int(row.get("remaining_move_budget", u.remaining_move_budget))
		u.attacked_this_side_turn = bool(
			row.get("attacked_this_side_turn", u.attacked_this_side_turn)
		)
		u.deploy_trigger_fired = bool(row.get("deploy_trigger_fired", u.deploy_trigger_fired))
		u.burn_stacks = int(row.get("burn_stacks", u.burn_stacks))
		u.frenzy_stacks = int(row.get("frenzy_stacks", u.frenzy_stacks))
		u.armor = int(row.get("armor", u.armor))
		u.death_cards_culled = bool(row.get("death_cards_culled", u.death_cards_culled))
		u.next_intent = int(row.get("next_intent", u.next_intent))
		u.stealthed = bool(row.get("stealthed", u.stealthed))
	board.restore_ignited_aoe_cells(snap.get("ignited", {}) as Dictionary)
	var deck := board.player_deck
	var deck_snap: Dictionary = snap.get("deck", {}) as Dictionary
	if deck != null and not deck_snap.is_empty():
		deck.hand.clear()
		for c in deck_snap.get("hand", []) as Array:
			deck.hand.append(c)
		deck.draw_pile.clear()
		for c in deck_snap.get("draw_pile", []) as Array:
			deck.draw_pile.append(c)
		deck.discard_pile.clear()
		for c in deck_snap.get("discard_pile", []) as Array:
			deck.discard_pile.append(c)
		deck.move_authorized = (deck_snap.get("move_authorized", {}) as Dictionary).duplicate()
		deck.attack_bonus_queues = (
			deck_snap.get("attack_bonus_queues", {}) as Dictionary
		).duplicate(true)
		deck.pending_attack_bonus = int(deck_snap.get("pending_attack_bonus", 0))
		deck.pending_aoe_burn_stacks = int(deck_snap.get("pending_aoe_burn_stacks", 0))
		deck.pending_volley = bool(deck_snap.get("pending_volley", false))


static func _unit_deltas_from_snap(board: TacticalBoard, snap: Dictionary) -> Dictionary:
	var before: Dictionary = {}
	for row_v in snap.get("units", []) as Array:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var u: TacticalUnitInstance = row.get("unit") as TacticalUnitInstance
		if u == null:
			continue
		before[u] = row
	var out: Dictionary = {}
	for u in board.units:
		var prev: Dictionary = before.get(u, {}) as Dictionary
		if prev.is_empty():
			continue
		var hp0 := int(prev.get("hp", u.hp))
		var armor0 := int(prev.get("armor", u.armor))
		var max0 := 0
		if u.def != null:
			max0 = u.def.max_hp + int(prev.get("max_hp_bonus", 0))
		var hp1 := u.hp
		var armor1 := u.armor
		var max1 := u.effective_max_hp()
		if hp0 == hp1 and armor0 == armor1 and max0 == max1:
			continue
		out[u] = {
			"hp": hp1,
			"max_hp": max1,
			"armor": armor1,
			"hp_delta": hp1 - hp0,
			"armor_delta": armor1 - armor0,
		}
	return out
