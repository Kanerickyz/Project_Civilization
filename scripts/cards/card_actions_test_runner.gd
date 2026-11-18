extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCardDeckScript := preload("res://scripts/cards/tactical_card_deck.gd")
const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")


func _initialize() -> void:
	if not _test_build_generic_plus_skills_player_only():
		quit(1)
		return
	if not _test_sts_draw_discard_and_reshuffle():
		quit(1)
		return
	if not _test_player_click_move_uses_budget():
		quit(1)
		return
	if not _test_player_death_removes_attack_and_skill():
		quit(1)
		return
	if not _test_player_death_cull_is_idempotent():
		quit(1)
		return
	if not _test_wardrum_death_removes_skill_draw_from_hand():
		quit(1)
		return
	if not _test_enemy_death_does_not_touch_deck():
		quit(1)
		return
	if not _test_end_turn_discards_hand():
		quit(1)
		return
	if not _test_player_side_turn_resets_move_budget():
		quit(1)
		return
	if not _test_player_move_budget_multi_step():
		quit(1)
		return
	if not _test_attack_card_authorizes_repeat_hits():
		quit(1)
		return
	if not _test_attack_card_stacks_on_same_unit():
		quit(1)
		return
	if not _test_ally_can_be_attacked():
		quit(1)
		return
	if not _test_wardrum_skill_redraw():
		quit(1)
		return
	if not _test_wardrum_skill_plays_on_board():
		quit(1)
		return
	if not _test_inspire_adds_frenzy_nearby():
		quit(1)
		return
	if not _test_strong_attack_bonus():
		quit(1)
		return
	if not _test_strong_attack_droppable_on_any_ally():
		quit(1)
		return
	if not _test_armor_skill_grants_on_ally():
		quit(1)
		return
	if not _test_ephemeral_attack_not_in_piles():
		quit(1)
		return
	print("CARD_ACTIONS_OK")
	quit(0)


func _vacate_cell(board: TacticalBoard, cell: Vector2i) -> void:
	var u := board.unit_at(cell)
	if u != null:
		u.hp = 0


## 邻格目标 + 清空击退落点，避免盾卫受阻×1.2干扰既有伤害/连攻断言。
func _place_adjacent_clear_knockback(
	board: TacticalBoard, attacker: TacticalUnitInstance, target: TacticalUnitInstance
) -> void:
	target.cell = attacker.cell + Vector2i(0, 1)
	_vacate_cell(board, target.cell + Vector2i(0, 1))


func _living_players(board: TacticalBoard) -> int:
	var n := 0
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			n += 1
	return n


func _test_build_generic_plus_skills_player_only() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var living_players := _living_players(board)
	var living_enemies := 0
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			living_enemies += 1
	if living_enemies <= 0:
		push_error("CardActions: demo board should have enemies")
		return false
	var skills := TacticalCardDeckScript.expected_skill_count_for_board(board)
	# 6 人：鼓手×2 /盾卫/大剑/爆爆/刺客有技，游侠无 → 6
	if skills != 6:
		push_error("CardActions: expected 6 skill cards, got %d" % skills)
		return false
	# 每人仅通用攻 1 + 主动技；无移动牌。
	var expected := living_players + skills
	if deck.draw_pile.size() != expected or deck.total_cards() != expected:
		push_error(
			"CardActions: expected %d cards, got %d"
			% [expected, deck.draw_pile.size()]
		)
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.MOVE) != 0:
		push_error("CardActions: deck must not include MOVE cards")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.ATTACK) != living_players:
		push_error("CardActions: attack count should equal living players")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_DRAW) != 1:
		push_error("CardActions: one wardrum draw skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_INSPIRE) != 1:
		push_error("CardActions: one wardrum inspire skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK) != 1:
		push_error("CardActions: one pekka strong attack expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_ARMOR) != 1:
		push_error("CardActions: one knight armor skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_BURN_ATTACK) != 1:
		push_error("CardActions: one boomling burn skill expected")
		return false
	for c in deck.draw_pile:
		if c.ephemeral:
			push_error("CardActions: build must not include ephemeral")
			return false
		if (
			c.kind == TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK
			and c.bound_unit_id != ""
		):
			push_error("CardActions: strong attack must be unbound")
			return false
		if (
			c.kind == TacticalActionCardScript.Kind.SKILL_ARMOR
			and (c.bound_unit_id != "" or c.armor_grant != 2)
		):
			push_error("CardActions: armor must be unbound with grant 2")
			return false
		if (
			c.kind == TacticalActionCardScript.Kind.SKILL_BURN_ATTACK
			and (c.bound_unit_id != "boomling" or c.aoe_burn_stacks != 3)
		):
			push_error("CardActions: burn skill must bind boomling with 3 stacks")
			return false
	return true


func _test_sts_draw_discard_and_reshuffle() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.draw_count = 5
	deck.build_from_living_player_units(board)
	var total := deck.total_cards()
	deck.begin_player_turn()
	if deck.hand.size() != 5:
		push_error("CardActions: first draw should yield 5, got %d" % deck.hand.size())
		return false
	while not deck.hand.is_empty():
		deck.play_hand_index(0)
	deck.draw_up_to(deck.draw_pile.size())
	var before_reshuffle_total := deck.total_cards()
	deck.discard_hand()
	var need := mini(5, before_reshuffle_total)
	var drawn := deck.draw_up_to(need)
	if drawn != need:
		push_error("CardActions: reshuffle draw expected %d got %d" % [need, drawn])
		return false
	if deck.total_cards() != before_reshuffle_total:
		push_error("CardActions: total cards must stay constant across reshuffle")
		return false
	if total < before_reshuffle_total:
		push_error("CardActions: unexpected card growth")
		return false
	return true


func _test_player_click_move_uses_budget() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	var unit: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			unit = u
			break
	if unit == null:
		push_error("CardActions: need archer for click-move test")
		return false
	if unit.remaining_move_budget != unit.def.move_range:
		push_error(
			"CardActions: player side start budget should be move_range %d, got %d"
			% [unit.def.move_range, unit.remaining_move_budget]
		)
		return false
	for u in board.living_units():
		if u != unit and (u.cell == Vector2i(2, 2) or u.cell == Vector2i(3, 2)):
			u.cell = Vector2i(0, 7) if u.faction == TacticalFactionScript.Id.PLAYER else Vector2i(9, 7)
	unit.cell = Vector2i(2, 2)
	var before := unit.remaining_move_budget
	if not board.try_move(unit, Vector2i(3, 2)):
		push_error("CardActions: click move should succeed with budget")
		return false
	if unit.remaining_move_budget != before - 1:
		push_error(
			"CardActions: budget should drop by path steps, got %d"
			% unit.remaining_move_budget
		)
		return false
	return true


func _test_player_death_removes_attack_and_skill() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	deck.begin_player_turn()
	var victim: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "knight":
			victim = u
			break
	if victim == null:
		return false
	var before_total := deck.total_cards()
	var before_armor := deck.count_kind(TacticalActionCardScript.Kind.SKILL_ARMOR)
	var removed := deck.on_player_unit_died(victim)
	# 攻 + 盾卫贡献的通用护甲
	if removed != 2:
		push_error("CardActions: knight death should remove 2, got %d" % removed)
		return false
	if deck.total_cards() != before_total - 2:
		push_error("CardActions: total after death mismatch")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_ARMOR) != before_armor - 1:
		push_error("CardActions: armor skill should drop by 1")
		return false
	return true


## 回归 PC-49：燃烧段开始会对尸体重复 purge；第二次不得再减攻。
func _test_player_death_cull_is_idempotent() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 49
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var victim: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "knight":
			victim = u
			break
	if victim == null:
		push_error("CardActions: knight missing for idempotent cull")
		return false
	var first := deck.on_player_unit_died(victim)
	if first != 2:
		push_error("CardActions: first knight cull should remove 2, got %d" % first)
		return false
	var attack_after := deck.count_kind(TacticalActionCardScript.Kind.ATTACK)
	var total_after := deck.total_cards()
	# 模拟段开始燃烧扫尸体：同一尸体再 purge。
	var second := deck.on_player_unit_died(victim)
	if second != 0:
		push_error("CardActions: repeat cull must be no-op, got %d" % second)
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.ATTACK) != attack_after:
		push_error("CardActions: repeat cull must not drop ATTACK")
		return false
	if deck.total_cards() != total_after:
		push_error("CardActions: repeat cull must not change total")
		return false
	if not victim.death_cards_culled:
		push_error("CardActions: death_cards_culled should stay true")
		return false
	return true


func _test_wardrum_death_removes_skill_draw_from_hand() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	# 把鸣鼓换手固定放进手牌，模拟「鼓手死后技能卡仍留手」回归。
	deck.hand.clear()
	deck.draw_pile.clear()
	deck.discard_pile.clear()
	deck.hand.append(TacticalActionCardScript.make_attack())
	deck.hand.append(TacticalActionCardScript.make_skill_draw("wardrum"))
	deck.hand.append(TacticalActionCardScript.make_skill_inspire("wardrum"))
	deck.draw_pile.append(TacticalActionCardScript.make_attack())
	var victim: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "wardrum":
			victim = u
			break
	if victim == null:
		push_error("CardActions: wardrum missing on demo board")
		return false
	var before := deck.total_cards()
	var removed := deck.on_player_unit_died(victim)
	# 攻 + 鸣鼓 + 鼓舞
	if removed != 3:
		push_error("CardActions: wardrum death should remove 3, got %d" % removed)
		return false
	if deck.total_cards() != before - 3:
		push_error("CardActions: wardrum death total mismatch")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_DRAW) != 0:
		push_error("CardActions: wardrum draw skill must leave all piles")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_INSPIRE) != 0:
		push_error("CardActions: wardrum inspire skill must leave all piles")
		return false
	for c in deck.hand:
		if (
			c.kind == TacticalActionCardScript.Kind.SKILL_DRAW
			or c.kind == TacticalActionCardScript.Kind.SKILL_INSPIRE
		):
			push_error("CardActions: wardrum skill still in hand after death")
			return false
	return true


func _test_enemy_death_does_not_touch_deck() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			foe = u
			break
	if foe == null:
		return false
	var before := deck.total_cards()
	var removed := deck.on_player_unit_died(foe)
	if removed != 0 or deck.total_cards() != before:
		push_error("CardActions: enemy death must not change player deck")
		return false
	return true


func _test_end_turn_discards_hand() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	deck.begin_player_turn()
	var hand_n := deck.hand.size()
	if hand_n <= 0:
		push_error("CardActions: expected hand before end turn")
		return false
	deck.end_player_turn()
	if not deck.hand.is_empty():
		push_error("CardActions: hand should empty on end turn")
		return false
	if deck.discard_pile.size() < hand_n:
		push_error("CardActions: hand should move to discard")
		return false
	deck.begin_player_turn()
	if deck.hand.is_empty():
		push_error("CardActions: second turn should draw")
		return false
	return true


func _test_player_side_turn_resets_move_budget() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var unit: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			unit = u
			break
	if unit == null:
		push_error("CardActions: need archer for budget reset test")
		return false
	unit.remaining_move_budget = 0
	if not board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: empty budget should block reachability")
		return false
	board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	var want := unit.def.action_move_budget()
	if unit.remaining_move_budget != want:
		push_error(
			"CardActions: side reset should refill budget %d, got %d"
			% [want, unit.remaining_move_budget]
		)
		return false
	if board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: after reset should have reachable cells")
		return false
	return true


func _test_player_move_budget_multi_step() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	var unit: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			unit = u
			break
	if unit == null:
		push_error("CardActions: need archer for multi-step move test")
		return false
	if unit.def.move_range != 3:
		push_error("CardActions: archer move_range should be 3")
		return false
	for u in board.living_units():
		if u != unit and (
			u.cell == Vector2i(2, 2) or u.cell == Vector2i(3, 2) or u.cell == Vector2i(4, 2)
		):
			u.cell = Vector2i(0, 7) if u.faction == TacticalFactionScript.Id.PLAYER else Vector2i(9, 7)
	unit.cell = Vector2i(2, 2)
	if not board.try_move(unit, Vector2i(3, 2)):
		push_error("CardActions: first budget step should succeed")
		return false
	if unit.remaining_move_budget != 2:
		push_error("CardActions: after 1 step budget should be 2, got %d" % unit.remaining_move_budget)
		return false
	if not board.try_move(unit, Vector2i(4, 2)):
		push_error("CardActions: second budget step should succeed")
		return false
	if unit.remaining_move_budget != 1:
		push_error("CardActions: after 2 steps budget should be 1, got %d" % unit.remaining_move_budget)
		return false
	return true


func _test_attack_card_authorizes_repeat_hits() -> bool:
	# 玩家无 attacked_this_side_turn 预算；多次攻击靠多次攻击卡授权。
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var knight: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "knight":
			knight = u
		elif u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "rider":
			foe = u
	if knight == null or foe == null:
		push_error("CardActions: need knight + foe rider")
		return false
	_place_adjacent_clear_knockback(board, knight, foe)
	foe.hp = 99
	if not deck.authorize_attack(knight):
		push_error("CardActions: first authorize_attack failed")
		return false
	if not deck.is_attack_authorized(knight):
		push_error("CardActions: knight should be attack-authorized")
		return false
	var first := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER, true
	)
	if not first["ok"]:
		push_error("CardActions: first authorized attack should succeed")
		return false
	if knight.attacked_this_side_turn:
		push_error("CardActions: player must not set attacked_this_side_turn")
		return false
	deck.consume_attack_authorization(knight)
	if deck.is_attack_authorized(knight):
		push_error("CardActions: attack auth must clear after one hit")
		return false
	# 再打一张攻击卡可再攻（击退后需摆回邻格）。
	_place_adjacent_clear_knockback(board, knight, foe)
	if not deck.authorize_attack(knight):
		push_error("CardActions: second authorize_attack failed")
		return false
	var second := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER, true
	)
	if not second["ok"]:
		push_error("CardActions: after second attack card, hit should succeed")
		return false
	deck.consume_attack_authorization(knight)
	return true


func _test_attack_card_stacks_on_same_unit() -> bool:
	# 同单位连拖多张攻击卡：队列累加，可连续结算多次（PC-36）。
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var knight: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "knight":
			knight = u
		elif u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "rider":
			foe = u
	if knight == null or foe == null:
		push_error("CardActions: stack test need knight + foe")
		return false
	_place_adjacent_clear_knockback(board, knight, foe)
	foe.hp = 99
	if not deck.authorize_attack(knight, 2):
		push_error("CardActions: stack first authorize failed")
		return false
	if not deck.authorize_attack(knight, 0):
		push_error("CardActions: stack second authorize failed")
		return false
	if deck.attack_authorization_count(knight) != 2:
		push_error("CardActions: expected 2 stacked attack charges")
		return false
	if deck.pending_attack_bonus != 2:
		push_error("CardActions: pending bonus should stay first-card +2")
		return false
	var first := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER, true, deck.pending_attack_bonus
	)
	if not first["ok"] or int(first["damage"]) != knight.effective_attack() + 2:
		push_error("CardActions: first stacked hit should use +2 bonus")
		return false
	var bonus1 := deck.consume_attack_authorization(knight)
	if bonus1 != 2:
		push_error("CardActions: consume should return first bonus 2")
		return false
	if not deck.is_attack_authorized(knight):
		push_error("CardActions: second charge must remain after first consume")
		return false
	if deck.pending_attack_bonus != 0:
		push_error("CardActions: pending should follow second charge bonus 0")
		return false
	_place_adjacent_clear_knockback(board, knight, foe)
	var second := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER, true, deck.pending_attack_bonus
	)
	if not second["ok"]:
		push_error("CardActions: second stacked hit should succeed")
		return false
	deck.consume_attack_authorization(knight)
	if deck.is_attack_authorized(knight):
		push_error("CardActions: queue must be empty after two consumes")
		return false
	deck.authorize_attack(knight, 1)
	deck.authorize_attack(knight, 3)
	deck.clear_attack_authorization(knight)
	if deck.is_attack_authorized(knight) or deck.pending_attack_bonus != 0:
		push_error("CardActions: clear_attack_authorization must wipe stack")
		return false
	return true


func _test_ally_can_be_attacked() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight: TacticalUnitInstance = null
	var archer: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		if u.def.id == "knight":
			knight = u
		elif u.def.id == "archer":
			archer = u
	if knight == null or archer == null:
		push_error("CardActions: need knight+archer")
		return false
	_place_adjacent_clear_knockback(board, knight, archer)
	var before := archer.hp
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, archer.cell, TacticalFactionScript.Id.PLAYER, true
	)
	if not res["ok"] or archer.hp >= before:
		push_error("CardActions: ally should be attackable for player")
		return false
	_place_adjacent_clear_knockback(board, knight, archer)
	var blocked := TacticalCombatScript.try_basic_attack(
		board, knight, archer.cell, TacticalFactionScript.Id.PLAYER, false
	)
	if blocked["ok"]:
		push_error("CardActions: allow_friendly=false must reject ally")
		return false
	return true


func _test_wardrum_skill_redraw() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	deck.begin_player_turn()
	# 塞一张技卡到手牌并打出换手；清空牌库迫使弃牌洗回。
	deck.hand.clear()
	deck.draw_pile.clear()
	deck.discard_pile.clear()
	deck.hand.append(TacticalActionCardScript.make_move())
	deck.hand.append(TacticalActionCardScript.make_attack())
	deck.hand.append(TacticalActionCardScript.make_move())
	deck.hand.append(TacticalActionCardScript.make_attack())
	deck.hand.append(TacticalActionCardScript.make_move())
	deck.hand.append(TacticalActionCardScript.make_skill_draw("wardrum"))
	# 弃牌里再放若干可洗回的永久卡，确保重抽有牌可抽。
	for _i in 4:
		deck.discard_pile.append(TacticalActionCardScript.make_move())
		deck.discard_pile.append(TacticalActionCardScript.make_attack())
	var skill_idx := deck.hand.size() - 1
	var skill := deck.play_hand_index(skill_idx)
	if skill == null or skill.kind != TacticalActionCardScript.Kind.SKILL_DRAW:
		push_error("CardActions: play skill_draw failed")
		return false
	# 打出后手牌剩 5，换手应弃掉再抽最多 5；鸣鼓换手须留在弃牌。
	var drawn := deck.resolve_wardrum_redraw()
	if deck.hand.size() != drawn:
		push_error("CardActions: redraw hand size mismatch")
		return false
	if drawn <= 0:
		push_error("CardActions: redraw should draw cards")
		return false
	var skill_in_discard := false
	for c in deck.discard_pile:
		if c == skill:
			skill_in_discard = true
			break
	if not skill_in_discard:
		push_error("CardActions: wardrum skill must stay in discard after redraw")
		return false
	for c in deck.hand:
		if c.kind == TacticalActionCardScript.Kind.SKILL_DRAW:
			push_error("CardActions: wardrum skill must not return to hand same turn")
			return false
	for c in deck.draw_pile:
		if c.kind == TacticalActionCardScript.Kind.SKILL_DRAW:
			push_error("CardActions: wardrum skill must not reshuffle into draw same turn")
			return false
	# 下一段开始应解除锁定；强制空库洗弃时技能须能进牌库/手牌。
	deck.end_player_turn()
	deck.draw_pile.clear()
	# 把非技能弃牌也清掉，只留锁定过的技能 + 若干饲料，验证解锁后可洗回。
	var feed: Array[TacticalActionCard] = []
	for c in deck.discard_pile:
		if c != skill:
			feed.append(c)
	deck.discard_pile.clear()
	deck.discard_pile.append(skill)
	for c in feed:
		deck.discard_pile.append(c)
	if deck.discard_pile.size() < 2:
		for _j in 3:
			deck.discard_pile.append(TacticalActionCardScript.make_move())
	deck.begin_player_turn()
	var unlocked_into_draw_or_hand := false
	for c in deck.hand:
		if c == skill:
			unlocked_into_draw_or_hand = true
	for c in deck.draw_pile:
		if c == skill:
			unlocked_into_draw_or_hand = true
	if not unlocked_into_draw_or_hand:
		push_error("CardActions: wardrum skill must be reshufflable next turn")
		return false
	return true


func _test_wardrum_skill_plays_on_board() -> bool:
	var card := TacticalActionCardScript.make_skill_draw("wardrum")
	if not card.plays_on_board():
		push_error("CardActions: wardrum skill must play on board")
		return false
	var strong := TacticalActionCardScript.make_skill_strong_attack(2)
	if strong.plays_on_board():
		push_error("CardActions: strong attack must still require a unit drop")
		return false
	var move := TacticalActionCardScript.make_move()
	if move.plays_on_board():
		push_error("CardActions: move must not play on empty board")
		return false
	# 归属仍绑鼓手，供死亡 cull。
	if card.bound_unit_id != "wardrum":
		push_error("CardActions: wardrum skill cull owner must stay wardrum")
		return false
	return true


func _test_inspire_adds_frenzy_nearby() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var drum: TacticalUnitInstance = null
	var ally: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		if u.def.id == "wardrum":
			drum = u
		elif ally == null:
			ally = u
	if drum == null or ally == null:
		push_error("CardActions: need wardrum + ally for inspire")
		return false
	ally.cell = drum.cell + Vector2i(1, 0)
	var card := TacticalActionCardScript.make_skill_inspire("wardrum")
	if card.plays_on_board():
		push_error("CardActions: inspire must require wardrum drop")
		return false
	if not card.can_drop_on(drum):
		push_error("CardActions: inspire must drop on wardrum")
		return false
	if card.can_drop_on(ally):
		push_error("CardActions: inspire must not drop on non-wardrum")
		return false
	var before := ally.frenzy_stacks
	var res: Dictionary = board.apply_inspire_frenzy(drum, 1)
	if not res.get("ok", false):
		push_error("CardActions: inspire apply failed")
		return false
	if ally.frenzy_stacks != before + 1:
		push_error("CardActions: inspire should +1 frenzy on neighbor")
		return false
	if drum.frenzy_stacks != 0:
		push_error("CardActions: inspire must not buff drummer self")
		return false
	# 伤害倍率：1 层 → ceil(base * 1.2)
	var power := ally.attack_power()
	var want := ceili(float(power) * 1.2)
	if ally.effective_attack() != want:
		push_error(
			"CardActions: frenzy effective_attack want %d got %d"
			% [want, ally.effective_attack()]
		)
		return false
	# 上限 15
	ally.frenzy_stacks = 15
	if ally.add_frenzy_stacks(3) != 0 or ally.frenzy_stacks != 15:
		push_error("CardActions: frenzy cap should be 15")
		return false
	return true


func _test_strong_attack_bonus() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "knight":
			knight = u
		elif u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "rider":
			foe = u
	if knight == null or foe == null:
		return false
	_place_adjacent_clear_knockback(board, knight, foe)
	foe.hp = 99
	var base := knight.attack_power()
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER, true, 2
	)
	if not res["ok"] or int(res["damage"]) != base + 2:
		push_error("CardActions: strong attack should deal base+2")
		return false
	return true


func _test_strong_attack_droppable_on_any_ally() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var card := TacticalActionCardScript.make_skill_strong_attack(2)
	if card.bound_unit_id != "":
		push_error("CardActions: strong attack factory must leave bound empty")
		return false
	var saw_player := false
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			if card.can_drop_on(u):
				push_error("CardActions: strong attack must not drop on foe")
				return false
			continue
		saw_player = true
		if not card.can_drop_on(u):
			push_error(
				"CardActions: strong attack must drop on any ally, failed on %s"
				% u.def.id
			)
			return false
	if not saw_player:
		push_error("CardActions: need player units for strong attack drop test")
		return false
	return true


func _test_armor_skill_grants_on_ally() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var card := TacticalActionCardScript.make_skill_armor()
	if card.kind != TacticalActionCardScript.Kind.SKILL_ARMOR or card.armor_grant != 2:
		push_error("CardActions: armor factory should grant 2")
		return false
	var ally: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			ally = u
			break
	if ally == null:
		push_error("CardActions: need archer for armor grant")
		return false
	if not card.can_drop_on(ally):
		push_error("CardActions: armor must drop on any ally")
		return false
	ally.add_armor(card.armor_grant)
	if ally.armor != 2:
		push_error("CardActions: armor grant should leave 2")
		return false
	ally.add_armor(card.armor_grant)
	if ally.armor != 4:
		push_error("CardActions: armor should stack to 4")
		return false
	return true


func _test_ephemeral_attack_not_in_piles() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	board.player_deck = TacticalCardDeckScript.new()
	var deck: TacticalCardDeck = board.player_deck
	deck.build_from_living_player_units(board)
	var before := deck.total_cards()
	deck.begin_player_turn()
	var archer: TacticalUnitInstance = null
	var foe: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			archer = u
		elif u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "rider":
			foe = u
	if archer == null or foe == null:
		push_error("CardActions: need archer + foe")
		return false
	foe.hp = 1
	foe.cell = archer.cell + Vector2i(0, 1)
	var hand_before := deck.hand.size()
	board.apply_damage(foe, 99, archer)
	if deck.hand.size() != hand_before + 1:
		push_error("CardActions: kill should add ephemeral attack to hand")
		return false
	var eph := deck.hand[deck.hand.size() - 1]
	if not eph.ephemeral or eph.kind != TacticalActionCardScript.Kind.ATTACK:
		push_error("CardActions: granted card must be ephemeral attack")
		return false
	# 打出销毁，不进弃。
	var idx := deck.hand.size() - 1
	var discard_before := deck.discard_pile.size()
	var played := deck.play_hand_index(idx)
	if played == null or not played.ephemeral:
		push_error("CardActions: play ephemeral failed")
		return false
	if deck.discard_pile.size() != discard_before:
		push_error("CardActions: ephemeral must not enter discard")
		return false
	# 再发一张，结束回合应销毁而非进弃。
	deck.add_ephemeral_attack_to_hand()
	var total_with_eph := deck.total_cards()
	deck.end_player_turn()
	if deck.total_cards() != total_with_eph - 1:
		push_error("CardActions: end turn should destroy ephemeral")
		return false
	if deck.total_cards() < before:
		# 开局抽了又弃，总数应回到 build 规模（不含临时卡）。
		pass
	return true
