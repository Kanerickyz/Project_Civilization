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
	if not _test_play_move_then_authorize_any_player():
		quit(1)
		return
	if not _test_player_death_removes_move_attack_and_skill():
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
	if not _test_move_card_grants_move_range():
		quit(1)
		return
	if not _test_move_card_one_step_only():
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
	if not _test_strong_attack_bonus():
		quit(1)
		return
	if not _test_strong_attack_droppable_on_any_ally():
		quit(1)
		return
	if not _test_ephemeral_attack_not_in_piles():
		quit(1)
		return
	print("CARD_ACTIONS_OK")
	quit(0)


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
	# 4 人：鼓手/盾卫/大剑有技，游侠无 → 3
	if skills != 3:
		push_error("CardActions: expected 3 skill cards, got %d" % skills)
		return false
	var expected := living_players * 2 + skills
	if deck.draw_pile.size() != expected or deck.total_cards() != expected:
		push_error(
			"CardActions: expected %d cards, got %d"
			% [expected, deck.draw_pile.size()]
		)
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.MOVE) != living_players:
		push_error("CardActions: move count should equal living players")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.ATTACK) != living_players:
		push_error("CardActions: attack count should equal living players")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_DRAW) != 1:
		push_error("CardActions: one wardrum skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK) != 2:
		push_error("CardActions: knight+pekka strong attack expected")
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


func _test_play_move_then_authorize_any_player() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	deck.begin_player_turn()
	var move_idx := -1
	for i in deck.hand.size():
		if deck.hand[i].kind == TacticalActionCardScript.Kind.MOVE:
			move_idx = i
			break
	if move_idx < 0:
		deck.discard_hand()
		deck.hand.append(TacticalActionCardScript.make_move())
		move_idx = 0
	var players: Array[TacticalUnitInstance] = []
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			players.append(u)
	if players.size() < 2:
		push_error("CardActions: need >=2 player units")
		return false
	var played := deck.play_hand_index(move_idx)
	if played == null or played.kind != TacticalActionCardScript.Kind.MOVE:
		push_error("CardActions: play move failed")
		return false
	if deck.is_move_authorized(players[0]) or deck.is_move_authorized(players[1]):
		push_error("CardActions: generic move must not auto-authorize")
		return false
	if not deck.authorize_move(players[1]):
		push_error("CardActions: authorize any player unit failed")
		return false
	if not deck.is_move_authorized(players[1]):
		push_error("CardActions: selected unit should be authorized")
		return false
	var cells := board.reachable_move_cells(players[1])
	if cells.is_empty():
		push_error("CardActions: authorized unit should have move cells")
		return false
	if not board.try_move(players[1], cells[0]):
		push_error("CardActions: authorized move should succeed")
		return false
	return true


func _test_player_death_removes_move_attack_and_skill() -> bool:
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
	var before_strong := deck.count_kind(TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK)
	var removed := deck.on_player_unit_died(victim)
	# 移+攻+盾卫贡献的通用加强攻
	if removed != 3:
		push_error("CardActions: knight death should remove 3, got %d" % removed)
		return false
	if deck.total_cards() != before_total - 3:
		push_error("CardActions: total after death mismatch")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK) != before_strong - 1:
		push_error("CardActions: strong attack skill should drop by 1")
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
	deck.hand.append(TacticalActionCardScript.make_move())
	deck.hand.append(TacticalActionCardScript.make_attack())
	deck.hand.append(TacticalActionCardScript.make_skill_draw("wardrum"))
	deck.draw_pile.append(TacticalActionCardScript.make_move())
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
	if removed != 3:
		push_error("CardActions: wardrum death should remove 3, got %d" % removed)
		return false
	if deck.total_cards() != before - 3:
		push_error("CardActions: wardrum death total mismatch")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_DRAW) != 0:
		push_error("CardActions: wardrum skill must leave all piles")
		return false
	for c in deck.hand:
		if c.kind == TacticalActionCardScript.Kind.SKILL_DRAW:
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


func _test_move_card_grants_move_range() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var unit: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			unit = u
			break
	if unit == null:
		push_error("CardActions: need archer for move-range grant test")
		return false
	unit.remaining_move_budget = 0
	if not board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: no allowance should block reachability")
		return false
	if not deck.authorize_move(unit):
		push_error("CardActions: authorize_move failed")
		return false
	var want := maxi(1, unit.def.move_range)
	if unit.remaining_move_budget != want:
		push_error(
			"CardActions: move card should grant move_range %d, got %d"
			% [want, unit.remaining_move_budget]
		)
		return false
	if board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: after authorize should have reachable cells")
		return false
	# 玩家无移力池：额度按 move_range，不按 action_move_budget / 满池重置语义。
	unit.remaining_move_budget = 0
	if not deck.authorize_move(unit):
		push_error("CardActions: second authorize_move failed")
		return false
	if unit.remaining_move_budget != want:
		push_error(
			"CardActions: re-authorize should grant move_range %d, got %d"
			% [want, unit.remaining_move_budget]
		)
		return false
	return true


func _test_move_card_one_step_only() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var deck: TacticalCardDeck = TacticalCardDeckScript.new()
	deck.build_from_living_player_units(board)
	var unit: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			unit = u
			break
	if unit == null:
		push_error("CardActions: need archer for one-step move test")
		return false
	if unit.def.move_range != 2:
		push_error("CardActions: archer move_range should be 2")
		return false
	if not deck.authorize_move(unit):
		push_error("CardActions: authorize_move failed")
		return false
	var dest := unit.cell + Vector2i(1, 0)
	if board.unit_at(dest) != null:
		dest = unit.cell + Vector2i(0, 1)
	if not board.try_move(unit, dest):
		push_error("CardActions: first move after card should succeed")
		return false
	deck.consume_move_authorization(unit)
	if deck.is_move_authorized(unit):
		push_error("CardActions: move auth must clear after one step")
		return false
	if unit.remaining_move_budget != 0:
		push_error("CardActions: move allowance must be 0 after consume")
		return false
	if not board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: no further moves without a new card")
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
	foe.cell = knight.cell + Vector2i(0, 1)
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
	# 再打一张攻击卡可再攻。
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
	foe.cell = knight.cell + Vector2i(0, 1)
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
	archer.cell = knight.cell + Vector2i(0, 1)
	var before := archer.hp
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, archer.cell, TacticalFactionScript.Id.PLAYER, true
	)
	if not res["ok"] or archer.hp >= before:
		push_error("CardActions: ally should be attackable for player")
		return false
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
	# 塞一张技卡到手牌并打出换手。
	deck.hand.clear()
	deck.hand.append(TacticalActionCardScript.make_move())
	deck.hand.append(TacticalActionCardScript.make_attack())
	deck.hand.append(TacticalActionCardScript.make_skill_draw("wardrum"))
	var skill_idx := 2
	var skill := deck.play_hand_index(skill_idx)
	if skill == null or skill.kind != TacticalActionCardScript.Kind.SKILL_DRAW:
		push_error("CardActions: play skill_draw failed")
		return false
	# 打出后手牌剩 2，换手应弃掉再抽最多 5。
	var drawn := deck.resolve_wardrum_redraw()
	if deck.hand.size() != drawn:
		push_error("CardActions: redraw hand size mismatch")
		return false
	if drawn <= 0:
		push_error("CardActions: redraw should draw cards")
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
	foe.cell = knight.cell + Vector2i(0, 1)
	foe.hp = 99
	var base := knight.effective_attack()
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
