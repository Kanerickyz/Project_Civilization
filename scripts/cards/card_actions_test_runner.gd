extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCardDeckScript := preload("res://scripts/cards/tactical_card_deck.gd")
const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")


func _initialize() -> void:
	if not _test_build_deck_size():
		quit(1)
		return
	if not _test_sts_draw_discard_and_reshuffle():
		quit(1)
		return
	if not _test_play_move_authorizes_budget():
		quit(1)
		return
	if not _test_death_purges_all_zones():
		quit(1)
		return
	if not _test_end_turn_discards_hand():
		quit(1)
		return
	print("CARD_ACTIONS_OK")
	quit(0)


func _test_build_deck_size() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var living_players := 0
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			living_players += 1
	var expected := living_players * 2
	if deck.draw_pile.size() != expected or deck.total_cards() != expected:
		push_error(
			"CardActions: expected %d cards in draw pile, got %d"
			% [expected, deck.draw_pile.size()]
		)
		return false
	if not deck.hand.is_empty() or not deck.discard_pile.is_empty():
		push_error("CardActions: hand/discard should start empty")
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
	if deck.draw_pile.size() != total - 5:
		push_error("CardActions: draw pile size after first draw")
		return false
	# Play all hand into discard, draw again until reshuffle needed.
	while not deck.hand.is_empty():
		deck.play_hand_index(0)
	if deck.discard_pile.size() != 5:
		push_error("CardActions: played cards should be in discard")
		return false
	# Exhaust remaining draw into hand/discard artificially then force reshuffle path.
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
	return true


func _test_play_move_authorizes_budget() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	deck.begin_player_turn()
	var move_idx := -1
	var move_unit: TacticalUnitInstance = null
	for i in deck.hand.size():
		var c: TacticalActionCard = deck.hand[i]
		if c.kind == TacticalActionCardScript.Kind.MOVE:
			move_idx = i
			move_unit = c.unit
			break
	if move_idx < 0 or move_unit == null:
		# Force a move card into hand if RNG dealt none.
		var player_unit: TacticalUnitInstance = null
		for u in board.living_units():
			if u.faction == TacticalFactionScript.Id.PLAYER:
				player_unit = u
				break
		if player_unit == null:
			push_error("CardActions: no player unit for move force")
			return false
		deck.discard_hand()
		deck.hand.append(
			TacticalActionCardScript.new(TacticalActionCardScript.Kind.MOVE, player_unit)
		)
		move_idx = 0
		move_unit = player_unit
	if deck.is_move_authorized(move_unit):
		push_error("CardActions: move should not be authorized before play")
		return false
	var played := deck.play_hand_index(move_idx)
	if played == null or played.kind != TacticalActionCardScript.Kind.MOVE:
		push_error("CardActions: play move failed")
		return false
	if not deck.is_move_authorized(move_unit):
		push_error("CardActions: move card should authorize unit")
		return false
	var cells := board.reachable_move_cells(move_unit)
	if cells.is_empty():
		push_error("CardActions: authorized unit should have move cells")
		return false
	if not board.try_move(move_unit, cells[0]):
		push_error("CardActions: authorized move should succeed via board.try_move")
		return false
	return true


func _test_death_purges_all_zones() -> bool:
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
	# Ensure victim cards exist in multiple zones: play one if in hand, leave rest.
	for i in range(deck.hand.size() - 1, -1, -1):
		if deck.hand[i].unit == victim:
			deck.play_hand_index(i)
			break
	var before := deck.total_cards()
	var removed := deck.remove_unit_cards(victim)
	if removed < 1:
		push_error("CardActions: expected to purge victim cards")
		return false
	if deck.total_cards() != before - removed:
		push_error("CardActions: purge total mismatch")
		return false
	for pile in [deck.hand, deck.draw_pile, deck.discard_pile]:
		for c in pile:
			if c.unit == victim:
				push_error("CardActions: victim card remained after purge")
				return false
	# Simulate kill via combat path still leaves board unit dead; purge is caller's job.
	victim.hp = 0
	var again := deck.remove_unit_cards(victim)
	if again != 0:
		push_error("CardActions: second purge should remove nothing")
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
	if not deck.move_authorized.is_empty():
		push_error("CardActions: move auth should clear on end turn")
		return false
	# Second turn draw works after discard.
	deck.begin_player_turn()
	if deck.hand.is_empty():
		push_error("CardActions: second turn should draw")
		return false
	return true
