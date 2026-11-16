extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCardDeckScript := preload("res://scripts/cards/tactical_card_deck.gd")
const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")


func _initialize() -> void:
	if not _test_build_generic_player_only():
		quit(1)
		return
	if not _test_sts_draw_discard_and_reshuffle():
		quit(1)
		return
	if not _test_play_move_then_authorize_any_player():
		quit(1)
		return
	if not _test_player_death_removes_one_each_kind():
		quit(1)
		return
	if not _test_enemy_death_does_not_touch_deck():
		quit(1)
		return
	if not _test_end_turn_discards_hand():
		quit(1)
		return
	if not _test_move_card_resets_budget():
		quit(1)
		return
	if not _test_attack_card_clears_flag_for_second_hit():
		quit(1)
		return
	print("CARD_ACTIONS_OK")
	quit(0)


func _test_build_generic_player_only() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var living_players := 0
	var living_enemies := 0
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			living_players += 1
		else:
			living_enemies += 1
	if living_enemies <= 0:
		push_error("CardActions: demo board should have enemies")
		return false
	var expected := living_players * 2
	if deck.draw_pile.size() != expected or deck.total_cards() != expected:
		push_error(
			"CardActions: expected %d cards (=player*2), got %d"
			% [expected, deck.draw_pile.size()]
		)
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.MOVE) != living_players:
		push_error("CardActions: move count should equal living players")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.ATTACK) != living_players:
		push_error("CardActions: attack count should equal living players")
		return false
	for c in deck.draw_pile:
		if c.display_label() != "移动" and c.display_label() != "攻击":
			push_error("CardActions: cards must be generic labels, got %s" % c.display_label())
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
		deck.hand.append(TacticalActionCardScript.new(TacticalActionCardScript.Kind.MOVE))
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
	# 通用卡：打出后尚未授权任何单位。
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


func _test_player_death_removes_one_each_kind() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	deck.begin_player_turn()
	var victim: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			victim = u
			break
	if victim == null:
		return false
	var before_move := deck.count_kind(TacticalActionCardScript.Kind.MOVE)
	var before_atk := deck.count_kind(TacticalActionCardScript.Kind.ATTACK)
	var before_total := deck.total_cards()
	var removed := deck.on_player_unit_died(victim)
	if removed != 2:
		push_error("CardActions: player death should remove 1 move + 1 attack, got %d" % removed)
		return false
	if deck.total_cards() != before_total - 2:
		push_error("CardActions: total after death mismatch")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.MOVE) != before_move - 1:
		push_error("CardActions: move count after death")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.ATTACK) != before_atk - 1:
		push_error("CardActions: attack count after death")
		return false
	victim.hp = 0
	var again := deck.on_player_unit_died(victim)
	# 仍可再减（通用卡不按实例绑定）；第二次按规则仍减各 1，若库中还有。
	# 这里只断言不会因敌方逻辑炸掉；重复调用对已死己方仍减张数是可接受的。
	if again < 0:
		push_error("CardActions: unexpected negative purge")
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


## 移力耗尽后再 authorize_move：剩余移力应重置为满池并可再移。
func _test_move_card_resets_budget() -> bool:
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
		push_error("CardActions: need archer for budget reset test")
		return false
	if not deck.authorize_move(unit):
		push_error("CardActions: first authorize_move failed")
		return false
	unit.remaining_move_budget = 0
	if not board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: exhausted budget should block reachability")
		return false
	if not deck.authorize_move(unit):
		push_error("CardActions: second authorize_move failed")
		return false
	var full := unit.def.action_move_budget()
	if unit.remaining_move_budget != full:
		push_error(
			"CardActions: second move card should reset budget to %d, got %d"
			% [full, unit.remaining_move_budget]
		)
		return false
	if board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: after reset should have reachable cells")
		return false
	return true


## 普攻后标记已攻；prepare_attack 清标记后可再攻（玩家卡路径）。
func _test_attack_card_clears_flag_for_second_hit() -> bool:
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
		elif u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "archer":
			foe = u
	if knight == null or foe == null:
		push_error("CardActions: need knight + foe archer")
		return false
	foe.cell = knight.cell + Vector2i(0, 1)
	foe.hp = 99
	var first := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not first["ok"] or not knight.attacked_this_side_turn:
		push_error("CardActions: first attack should succeed and set flag")
		return false
	var blocked := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if blocked["ok"]:
		push_error("CardActions: without card, second attack must fail (AI path)")
		return false
	if not deck.prepare_attack(knight):
		push_error("CardActions: prepare_attack failed")
		return false
	if knight.attacked_this_side_turn:
		push_error("CardActions: prepare_attack should clear attacked flag")
		return false
	var second := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not second["ok"]:
		push_error("CardActions: after attack card, second hit should succeed")
		return false
	return true
