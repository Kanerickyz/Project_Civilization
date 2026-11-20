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
	var unit_deltas: Dictionary = {}
	var visuals := {}
	if bool(atk.get("ok", false)):
		if include_attack_card_passive:
			var card_fx: Array = []
			TacticalAbilitySystemScript.process_player_attack_card_played(board, card_fx)
		unit_deltas = _unit_deltas_from_snap(board, snap)
		visuals = _visuals_from_attack(atk, attacker, snap, unit_deltas)
	_restore(board, snap)
	board.end_preview_mute()
	if not bool(atk.get("ok", false)):
		return _empty_preview(str(atk.get("log", "无法攻击")))
	return _pack_preview(true, str(atk.get("log", "")), unit_deltas, target_cell, visuals)


static func preview_charge(
	board: TacticalBoard, knight: TacticalUnitInstance, dir_cell: Vector2i
) -> Dictionary:
	if board == null or knight == null:
		return _empty_preview("无效冲撞预览")
	var snap := _snapshot(board)
	board.begin_preview_mute()
	var res := TacticalCombatScript.try_knight_charge(board, knight, dir_cell)
	var unit_deltas: Dictionary = {}
	var visuals := {}
	if bool(res.get("ok", false)):
		unit_deltas = _unit_deltas_from_snap(board, snap)
		visuals = _visuals_from_charge(res, knight, snap, unit_deltas)
	_restore(board, snap)
	board.end_preview_mute()
	if not bool(res.get("ok", false)):
		return _empty_preview(str(res.get("log", "无法冲撞")))
	return _pack_preview(true, str(res.get("log", "")), unit_deltas, dir_cell, visuals)


static func preview_heal_potion(
	board: TacticalBoard, caster: TacticalUnitInstance, cell: Vector2i
) -> Dictionary:
	if board == null or caster == null:
		return _empty_preview("无效恢复预览")
	var snap := _snapshot(board)
	board.begin_preview_mute()
	var res := board.apply_heal_potion(caster, cell, 2, 1)
	var unit_deltas: Dictionary = {}
	if bool(res.get("ok", false)):
		unit_deltas = _unit_deltas_from_snap(board, snap)
	_restore(board, snap)
	board.end_preview_mute()
	if not bool(res.get("ok", false)):
		return _empty_preview(str(res.get("log", "无法恢复")))
	var visuals := {
		"highlights": _highlights_from_deltas(unit_deltas, "heal"),
		"ghosts": [],
		"lines": [],
		"mark_cells": [cell],
	}
	return _pack_preview(true, str(res.get("log", "")), unit_deltas, cell, visuals)


static func preview_inspire(board: TacticalBoard, drummer: TacticalUnitInstance) -> Dictionary:
	if board == null or drummer == null:
		return _empty_preview("无效鼓舞预览")
	var snap := _snapshot(board)
	board.begin_preview_mute()
	var res := board.apply_inspire_frenzy(drummer, 1)
	var unit_deltas: Dictionary = {}
	var buff_units: Array = []
	if bool(res.get("ok", false)):
		unit_deltas = _unit_deltas_from_snap(board, snap)
		for fx in res.get("passive_fx", []) as Array:
			if not (fx is Dictionary):
				continue
			var fx_cell: Vector2i = (fx as Dictionary).get("cell", Vector2i(-1, -1)) as Vector2i
			var u := board.unit_at(fx_cell)
			if u != null and not buff_units.has(u):
				buff_units.append(u)
	_restore(board, snap)
	board.end_preview_mute()
	if not bool(res.get("ok", false)):
		return _empty_preview(str(res.get("log", "无法鼓舞")))
	var highlights: Dictionary = {}
	for u in buff_units:
		highlights[u] = "buff"
	highlights[drummer] = "caster"
	return _pack_preview(
		true,
		str(res.get("log", "")),
		unit_deltas,
		drummer.cell,
		{"highlights": highlights, "ghosts": [], "lines": [], "mark_cells": []}
	)


static func preview_armor(target: TacticalUnitInstance, amount: int) -> Dictionary:
	if target == null or not target.is_alive():
		return _empty_preview("无效护甲预览")
	var grant := maxi(1, amount)
	var after_armor := target.armor + grant
	var deltas := {
		target: {
			"hp": target.hp,
			"max_hp": target.effective_max_hp(),
			"armor": after_armor,
			"hp_delta": 0,
			"armor_delta": grant,
		}
	}
	return _pack_preview(
		true,
		"%s +%d 护甲" % [target.def.display_name, grant],
		deltas,
		target.cell,
		{
			"highlights": {target: "buff"},
			"ghosts": [],
			"lines": [],
			"mark_cells": [],
		}
	)


static func preview_move_authorize(unit: TacticalUnitInstance) -> Dictionary:
	if unit == null or not unit.is_alive() or unit.def == null:
		return _empty_preview("无效移动预览")
	return _pack_preview(
		true,
		"%s 获移动授权" % unit.def.display_name,
		{},
		unit.cell,
		{
			"highlights": {unit: "caster"},
			"ghosts": [],
			"lines": [],
			"mark_cells": [],
			"show_reachable": true,
			"move_unit": unit,
		}
	)


static func preview_move_step(
	board: TacticalBoard, unit: TacticalUnitInstance, dest: Vector2i
) -> Dictionary:
	if board == null or unit == null or not unit.is_alive():
		return _empty_preview("无效落点")
	var reachable := board.reachable_move_cells(unit)
	if not (dest in reachable):
		return _empty_preview("不可达")
	return _pack_preview(
		true,
		"%s → (%d,%d)" % [unit.def.display_name, dest.x, dest.y],
		{},
		dest,
		{
			"highlights": {unit: "caster"},
			"ghosts": [{"unit": unit, "cell": dest, "kind": "move"}],
			"lines": [{"from": unit.cell, "to": dest, "kind": "move"}],
			"mark_cells": [dest],
		}
	)


static func preview_stealth(target: TacticalUnitInstance) -> Dictionary:
	if target == null or not target.is_alive():
		return _empty_preview("无效隐身预览")
	return _pack_preview(
		true,
		"%s 隐身" % target.def.display_name,
		{},
		target.cell,
		{
			"highlights": {target: "stealth"},
			"ghosts": [],
			"lines": [],
			"mark_cells": [],
		}
	)


static func preview_skill_draw(drummer: TacticalUnitInstance = null) -> Dictionary:
	var highlights: Dictionary = {}
	var hover := Vector2i(-1, -1)
	if drummer != null and drummer.is_alive():
		highlights[drummer] = "caster"
		hover = drummer.cell
	return _pack_preview(
		true,
		"鸣鼓换手",
		{},
		hover,
		{"highlights": highlights, "ghosts": [], "lines": [], "mark_cells": []}
	)


static func preview_attack_authorize(attacker: TacticalUnitInstance) -> Dictionary:
	if attacker == null or not attacker.is_alive():
		return _empty_preview("无效攻击授权")
	return _pack_preview(
		true,
		"攻击授权",
		{},
		attacker.cell,
		{
			"highlights": {attacker: "caster"},
			"ghosts": [],
			"lines": [],
			"mark_cells": [],
			"show_attack_range": true,
			"attack_unit": attacker,
		}
	)


static func _empty_preview(log: String) -> Dictionary:
	return _pack_preview(false, log, {}, Vector2i(-1, -1), {})


static func _pack_preview(
	ok: bool,
	log: String,
	unit_deltas: Dictionary,
	hover_cell: Variant,
	visuals: Dictionary
) -> Dictionary:
	return {
		"ok": ok,
		"log": log,
		"unit_deltas": unit_deltas,
		"hover_cell": hover_cell,
		"highlights": visuals.get("highlights", {}),
		"ghosts": visuals.get("ghosts", []),
		"lines": visuals.get("lines", []),
		"mark_cells": visuals.get("mark_cells", []),
		"show_reachable": bool(visuals.get("show_reachable", false)),
		"move_unit": visuals.get("move_unit", null),
		"show_attack_range": bool(visuals.get("show_attack_range", false)),
		"attack_unit": visuals.get("attack_unit", null),
	}


static func _highlights_from_deltas(unit_deltas: Dictionary, default_kind: String) -> Dictionary:
	var out: Dictionary = {}
	for u in unit_deltas.keys():
		if not (u is TacticalUnitInstance):
			continue
		var d: Dictionary = unit_deltas[u] as Dictionary
		var hp_d := int(d.get("hp_delta", 0))
		var ar_d := int(d.get("armor_delta", 0))
		var kind := default_kind
		if int(d.get("hp", 1)) <= 0:
			kind = "kill"
		elif hp_d < 0 or ar_d < 0:
			kind = "damage"
		elif hp_d > 0:
			kind = "heal"
		elif ar_d > 0:
			kind = "buff"
		out[u] = kind
	return out


static func _cell_before(snap: Dictionary, unit: TacticalUnitInstance) -> Vector2i:
	for row_v in snap.get("units", []) as Array:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		if row.get("unit") == unit:
			return row.get("cell", unit.cell) as Vector2i
	return unit.cell if unit != null else Vector2i(-1, -1)


static func _visuals_from_attack(
	atk: Dictionary,
	attacker: TacticalUnitInstance,
	snap: Dictionary,
	unit_deltas: Dictionary
) -> Dictionary:
	var highlights := _highlights_from_deltas(unit_deltas, "damage")
	if attacker != null:
		highlights[attacker] = "caster"
	var ghosts: Array = []
	var lines: Array = []
	var marks: Array = []
	var target: TacticalUnitInstance = atk.get("target") as TacticalUnitInstance
	var hit_cell: Vector2i = atk.get("knockback_from", Vector2i(-1, -1)) as Vector2i
	if hit_cell.x < 0 and target != null:
		hit_cell = _cell_before(snap, target)
	var atk_from := _cell_before(snap, attacker)
	if hit_cell.x >= 0:
		lines.append({"from": atk_from, "to": hit_cell, "kind": "attack"})
		marks.append(hit_cell)
	if bool(atk.get("knockback_moved", false)) and target != null:
		var kto: Vector2i = atk.get("knockback_to", Vector2i(-1, -1)) as Vector2i
		if kto.x >= 0:
			ghosts.append({"unit": target, "cell": kto, "kind": "knockback"})
			marks.append(kto)
	elif bool(atk.get("knockback_blocked", false)):
		var blocked: Vector2i = atk.get("knockback_to", Vector2i(-1, -1)) as Vector2i
		if blocked.x >= 0:
			marks.append(blocked)
	var col: TacticalUnitInstance = atk.get("collision_target") as TacticalUnitInstance
	if col != null:
		highlights[col] = "damage" if not bool(atk.get("collision_killed", false)) else "kill"
	for hit in atk.get("volley_hits", []) as Array:
		if not (hit is Dictionary):
			continue
		var vu: TacticalUnitInstance = (hit as Dictionary).get("unit") as TacticalUnitInstance
		var vcell: Vector2i = (hit as Dictionary).get("cell", Vector2i(-1, -1)) as Vector2i
		if vu == null:
			continue
		if bool((hit as Dictionary).get("killed", false)):
			highlights[vu] = "kill"
		elif not highlights.has(vu):
			highlights[vu] = "damage"
		if vcell.x >= 0:
			marks.append(vcell)
	if bool(atk.get("killed", false)) and target != null:
		highlights[target] = "kill"
	return {
		"highlights": highlights,
		"ghosts": ghosts,
		"lines": lines,
		"mark_cells": marks,
	}


static func _visuals_from_charge(
	res: Dictionary,
	knight: TacticalUnitInstance,
	snap: Dictionary,
	unit_deltas: Dictionary
) -> Dictionary:
	var highlights := _highlights_from_deltas(unit_deltas, "damage")
	if knight != null:
		highlights[knight] = "caster"
	var ghosts: Array = []
	var lines: Array = []
	var marks: Array = []
	var from_cell: Vector2i = res.get("from_cell", _cell_before(snap, knight)) as Vector2i
	var to_cell: Vector2i = res.get("to_cell", from_cell) as Vector2i
	if to_cell != from_cell:
		ghosts.append({"unit": knight, "cell": to_cell, "kind": "charge"})
		lines.append({"from": from_cell, "to": to_cell, "kind": "move"})
		marks.append(to_cell)
	for hit in res.get("hits", []) as Array:
		if not (hit is Dictionary):
			continue
		var vu: TacticalUnitInstance = (hit as Dictionary).get("unit") as TacticalUnitInstance
		var vcell: Vector2i = (hit as Dictionary).get("cell", Vector2i(-1, -1)) as Vector2i
		if vu == null:
			continue
		if bool((hit as Dictionary).get("killed", false)):
			highlights[vu] = "kill"
		else:
			highlights[vu] = "damage"
		if vcell.x >= 0:
			marks.append(vcell)
		if bool((hit as Dictionary).get("knock_moved", false)):
			var kto: Vector2i = (hit as Dictionary).get("knock_to", Vector2i(-1, -1)) as Vector2i
			if kto.x >= 0:
				ghosts.append({"unit": vu, "cell": kto, "kind": "knockback"})
	if bool(res.get("self_killed", false)) and knight != null:
		highlights[knight] = "kill"
	elif int(res.get("self_damage", 0)) > 0 and knight != null:
		highlights[knight] = "damage"
	return {
		"highlights": highlights,
		"ghosts": ghosts,
		"lines": lines,
		"mark_cells": marks,
	}


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
