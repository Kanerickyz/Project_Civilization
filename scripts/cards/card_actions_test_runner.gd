extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalCardDeckScript := preload("res://scripts/cards/tactical_card_deck.gd")
const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")


func _initialize() -> void:
	if not _test_build_generic_plus_skills_player_only():
		quit(1)
		return
	if not _test_sts_draw_discard_and_reshuffle():
		quit(1)
		return
	if not _test_player_side_start_has_no_free_move():
		quit(1)
		return
	if not _test_move_card_grants_move_range():
		quit(1)
		return
	if not _test_move_card_one_step_only():
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
	if not _test_player_side_turn_zeros_move_budget():
		quit(1)
		return
	if not _test_opponent_side_turn_resets_move_budget():
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
	if not _test_bound_skills_play_free():
		quit(1)
		return
	if not _test_skill_invalid_release_cell():
		quit(1)
		return
	if not _test_inspire_adds_frenzy_nearby():
		quit(1)
		return
	if not _test_volley_binds_archer_only():
		quit(1)
		return
	if not _test_charge_binds_knight_only():
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
	if not _test_heal_potion_skill():
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
	# 6 人：鼓手×2 /盾卫护甲+冲撞 /大剑×2 /爆爆/游侠齐发/医师药水×2 → 10（刺客未编入阵容）
	if skills != 10:
		push_error("CardActions: expected 10 skill cards, got %d" % skills)
		return false
	# 每人通用移+攻各 1 + 主动技；玩家仅经移动卡移动。
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
		push_error("CardActions: one wardrum draw skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_INSPIRE) != 1:
		push_error("CardActions: one wardrum inspire skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_STRONG_ATTACK) != 2:
		push_error("CardActions: two pekka strong attack expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_ARMOR) != 1:
		push_error("CardActions: one knight armor skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_CHARGE) != 1:
		push_error("CardActions: one knight charge skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_BURN_ATTACK) != 1:
		push_error("CardActions: one boomling burn skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_VOLLEY) != 1:
		push_error("CardActions: one archer volley skill expected")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_HEAL_POTION) != 2:
		push_error("CardActions: two healer potion skills expected")
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
			c.kind == TacticalActionCardScript.Kind.SKILL_CHARGE
			and c.bound_unit_id != "knight"
		):
			push_error("CardActions: charge must bind knight")
			return false
		if (
			c.kind == TacticalActionCardScript.Kind.SKILL_BURN_ATTACK
			and (c.bound_unit_id != "boomling" or c.aoe_burn_stacks != 3)
		):
			push_error("CardActions: burn skill must bind boomling with 3 stacks")
			return false
		if (
			c.kind == TacticalActionCardScript.Kind.SKILL_VOLLEY
			and c.bound_unit_id != "archer"
		):
			push_error("CardActions: volley must bind archer")
			return false
		if (
			c.kind == TacticalActionCardScript.Kind.SKILL_HEAL_POTION
			and c.bound_unit_id != "healer"
		):
			push_error("CardActions: heal potion must bind healer")
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


func _test_player_side_start_has_no_free_move() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	var unit: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			unit = u
			break
	if unit == null:
		push_error("CardActions: need archer for no-free-move test")
		return false
	if unit.remaining_move_budget != 0:
		push_error(
			"CardActions: player side start budget should be 0, got %d"
			% unit.remaining_move_budget
		)
		return false
	if not board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: without move card should have no reachable cells")
		return false
	for u in board.living_units():
		if u != unit and (u.cell == Vector2i(2, 2) or u.cell == Vector2i(3, 2)):
			u.cell = Vector2i(0, 7) if u.faction == TacticalFactionScript.Id.PLAYER else Vector2i(9, 7)
	unit.cell = Vector2i(2, 2)
	if board.try_move(unit, Vector2i(3, 2)):
		push_error("CardActions: try_move without card budget must fail")
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
	if unit.def.move_range != 3:
		push_error("CardActions: archer move_range should be 3")
		return false
	if not deck.authorize_move(unit):
		push_error("CardActions: authorize_move failed")
		return false
	for u in board.living_units():
		if u != unit and (u.cell == Vector2i(2, 2) or u.cell == Vector2i(3, 2)):
			u.cell = Vector2i(0, 7) if u.faction == TacticalFactionScript.Id.PLAYER else Vector2i(9, 7)
	unit.cell = Vector2i(2, 2)
	var dest := Vector2i(3, 2)
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
	var before_charge := deck.count_kind(TacticalActionCardScript.Kind.SKILL_CHARGE)
	var removed := deck.on_player_unit_died(victim)
	# 移 + 攻 + 通用护甲 + 绑定冲撞
	if removed != 4:
		push_error("CardActions: knight death should remove 4, got %d" % removed)
		return false
	if deck.total_cards() != before_total - 4:
		push_error("CardActions: total after death mismatch")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_ARMOR) != before_armor - 1:
		push_error("CardActions: armor skill should drop by 1")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_CHARGE) != before_charge - 1:
		push_error("CardActions: charge skill should drop by 1")
		return false
	return true


## 回归 PC-49：燃烧段开始会对尸体重复 purge；第二次不得再减 MOVE/攻。
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
	if first != 4:
		push_error("CardActions: first knight cull should remove 4, got %d" % first)
		return false
	var move_after := deck.count_kind(TacticalActionCardScript.Kind.MOVE)
	var attack_after := deck.count_kind(TacticalActionCardScript.Kind.ATTACK)
	var total_after := deck.total_cards()
	# 模拟段开始燃烧扫尸体：同一尸体再 purge。
	var second := deck.on_player_unit_died(victim)
	if second != 0:
		push_error("CardActions: repeat cull must be no-op, got %d" % second)
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.MOVE) != move_after:
		push_error("CardActions: repeat cull must not drop MOVE")
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
	deck.hand.append(TacticalActionCardScript.make_move())
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
	# 移 + 攻 + 鸣鼓 + 鼓舞
	if removed != 4:
		push_error("CardActions: wardrum death should remove 4, got %d" % removed)
		return false
	if deck.total_cards() != before - 4:
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


func _test_player_side_turn_zeros_move_budget() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var unit: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			unit = u
			break
	if unit == null:
		push_error("CardActions: need archer for player budget zero test")
		return false
	unit.remaining_move_budget = 3
	board.reset_side_turn_flags(TacticalFactionScript.Id.PLAYER)
	if unit.remaining_move_budget != 0:
		push_error(
			"CardActions: player side reset should zero budget, got %d"
			% unit.remaining_move_budget
		)
		return false
	if not board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: after player reset should have no free reachable cells")
		return false
	return true


func _test_opponent_side_turn_resets_move_budget() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var unit: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == "rider":
			unit = u
			break
	if unit == null:
		push_error("CardActions: need rider for opponent budget reset test")
		return false
	unit.remaining_move_budget = 0
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	var want := unit.def.action_move_budget()
	if unit.remaining_move_budget != want:
		push_error(
			"CardActions: opponent side reset should refill budget %d, got %d"
			% [want, unit.remaining_move_budget]
		)
		return false
	if board.reachable_move_cells(unit).is_empty():
		push_error("CardActions: after opponent reset should have reachable cells")
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
	var armor := TacticalActionCardScript.make_skill_armor()
	if armor.plays_on_board():
		push_error("CardActions: armor must still require a unit drop")
		return false
	var attack := TacticalActionCardScript.make_attack()
	if attack.plays_on_board():
		push_error("CardActions: attack must not play free")
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


func _test_volley_binds_archer_only() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer: TacticalUnitInstance = null
	var other: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		if u.def.id == "archer":
			archer = u
		elif other == null:
			other = u
	if archer == null or other == null:
		push_error("CardActions: need archer + other")
		return false
	var card := TacticalActionCardScript.make_skill_volley("archer")
	if not card.is_attack_aim() or not card.is_active_skill():
		push_error("CardActions: volley must be attack-aim skill")
		return false
	if not card.plays_on_board():
		push_error("CardActions: volley must play free")
		return false
	if card.find_bound_caster(board) != archer:
		push_error("CardActions: volley caster must resolve to archer")
		return false
	# 自由打出：落在任意存活单位也算有效松手区。
	if not card.can_drop_on(archer) or not card.can_drop_on(other):
		push_error("CardActions: volley free play accepts any living drop")
		return false
	# 授权队列须带上 volley，结算时 pending_volley 为真。
	var deck := TacticalCardDeckScript.new()
	if not deck.authorize_attack(archer, 0, 0, true):
		push_error("CardActions: volley authorize_attack failed")
		return false
	if not deck.pending_volley:
		push_error("CardActions: pending_volley must be true after volley auth")
		return false
	var foe: TacticalUnitInstance = null
	var side_a: TacticalUnitInstance = null
	var side_b: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.OPPONENT:
			continue
		if foe == null:
			foe = u
		elif side_a == null:
			side_a = u
		elif side_b == null:
			side_b = u
			break
	if foe == null or side_a == null or side_b == null:
		push_error("CardActions: volley auth needs 3 foes")
		return false
	board.set_terrain_cells({})
	archer.cell = Vector2i(2, 2)
	foe.cell = Vector2i(4, 2)
	side_a.cell = Vector2i(4, 1)
	side_b.cell = Vector2i(4, 3)
	foe.hp = 99
	side_a.hp = 99
	side_b.hp = 99
	var splash := archer.effective_attack()
	var atk := TacticalCombatScript.try_basic_attack(
		board,
		archer,
		foe.cell,
		TacticalFactionScript.Id.PLAYER,
		true,
		deck.pending_attack_bonus,
		deck.pending_aoe_burn_stacks,
		deck.pending_volley
	)
	if not atk.get("ok", false) or (atk.get("volley_hits", []) as Array).size() != 2:
		push_error("CardActions: authorized volley must splash 2 sides")
		return false
	if side_a.hp != 99 - splash or side_b.hp != 99 - splash:
		push_error("CardActions: authorized volley side dmg want %d" % splash)
		return false
	deck.consume_attack_authorization(archer)
	if deck.pending_volley:
		push_error("CardActions: pending_volley must clear after consume")
		return false
	var preview: Array[Vector2i] = card.release_preview_cells(board)
	if preview.is_empty():
		push_error("CardActions: volley preview must show attack range")
		return false
	return true


func _test_charge_binds_knight_only() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight: TacticalUnitInstance = null
	var other: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		if u.def.id == "knight":
			knight = u
		elif other == null:
			other = u
	if knight == null or other == null:
		push_error("CardActions: need knight + other")
		return false
	var card := TacticalActionCardScript.make_skill_charge("knight")
	if card.is_attack_aim() or not card.is_charge_aim() or not card.is_active_skill():
		push_error("CardActions: charge must be charge-aim skill")
		return false
	if not card.plays_on_board():
		push_error("CardActions: charge must play free")
		return false
	if card.find_bound_caster(board) != knight:
		push_error("CardActions: charge caster must resolve to knight")
		return false
	if not card.can_drop_on(knight) or not card.can_drop_on(other):
		push_error("CardActions: charge free play accepts any living drop")
		return false
	var preview: Array[Vector2i] = card.release_preview_cells(board)
	if preview.is_empty() or not (knight.cell + Vector2i(1, 0) in preview):
		push_error("CardActions: charge preview must show direction cells")
		return false
	return true


func _test_bound_skills_play_free() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var inspire := TacticalActionCardScript.make_skill_inspire("wardrum")
	var burn := TacticalActionCardScript.make_skill_burn_attack("boomling", 3)
	var stealth := TacticalActionCardScript.make_skill_stealth("assassin")
	var volley := TacticalActionCardScript.make_skill_volley("archer")
	var charge := TacticalActionCardScript.make_skill_charge("knight")
	var potion := TacticalActionCardScript.make_skill_heal_potion("healer")
	if (
		not inspire.plays_on_board()
		or not burn.plays_on_board()
		or not stealth.plays_on_board()
		or not volley.plays_on_board()
		or not charge.plays_on_board()
		or not potion.plays_on_board()
	):
		push_error("CardActions: bound skills must play free (plays_on_board)")
		return false
	var drum := inspire.find_bound_caster(board)
	var boom := burn.find_bound_caster(board)
	var archer := volley.find_bound_caster(board)
	var knight := charge.find_bound_caster(board)
	var healer := potion.find_bound_caster(board)
	if drum == null or boom == null or archer == null or knight == null or healer == null:
		push_error("CardActions: bound casters missing on demo board")
		return false
	# 刺客未编入可部署阵容；卡工厂仍可用，场上无施法者时解析为 null。
	if stealth.find_bound_caster(board) != null:
		push_error("CardActions: assassin must not be on default roster")
		return false
	var inspire_cells: Array[Vector2i] = inspire.release_preview_cells(board)
	if inspire_cells.is_empty() or not (drum.cell in inspire_cells):
		push_error("CardActions: inspire preview must include drummer cell")
		return false
	var burn_cells: Array[Vector2i] = burn.release_preview_cells(board)
	if burn_cells.is_empty():
		push_error("CardActions: burn preview must show attack range")
		return false
	# 自由打出后鼓舞仍按鼓手结算。
	var ally: TacticalUnitInstance = null
	for u in board.living_units():
		if (
			u.faction == TacticalFactionScript.Id.PLAYER
			and u != drum
			and GridMathScript.chebyshev(drum.cell, u.cell) <= 1
		):
			ally = u
			break
	if ally == null:
		for u in board.living_units():
			if u.faction == TacticalFactionScript.Id.PLAYER and u != drum:
				ally = u
				break
		if ally == null:
			push_error("CardActions: need ally for free inspire")
			return false
		ally.cell = drum.cell + Vector2i(1, 0)
	var before := ally.frenzy_stacks
	var res: Dictionary = board.apply_inspire_frenzy(drum, 1)
	if not res.get("ok", false) or ally.frenzy_stacks != before + 1:
		push_error("CardActions: free inspire should buff neighbor via bound caster")
		return false
	return true


## 非通用技：规则格外落点须判无效（拖放回手）；规则格内有效。
func _test_skill_invalid_release_cell() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var volley := TacticalActionCardScript.make_skill_volley("archer")
	var charge := TacticalActionCardScript.make_skill_charge("knight")
	var inspire := TacticalActionCardScript.make_skill_inspire("wardrum")
	var wardrum := TacticalActionCardScript.make_skill_draw("wardrum")
	var potion := TacticalActionCardScript.make_skill_heal_potion("healer")
	var archer := volley.find_bound_caster(board)
	var knight := charge.find_bound_caster(board)
	var drum := inspire.find_bound_caster(board)
	var healer := potion.find_bound_caster(board)
	if archer == null or knight == null or drum == null or healer == null:
		push_error("CardActions: casters missing for invalid-release test")
		return false
	var volley_cells: Array[Vector2i] = volley.release_preview_cells(board)
	if volley_cells.is_empty():
		push_error("CardActions: volley needs release cells")
		return false
	if not volley.is_valid_release_cell(board, volley_cells[0]):
		push_error("CardActions: volley rule cell must be valid release")
		return false
	# 找一格不在发射带内。
	var outside := Vector2i(-1, -1)
	for gx in range(board.grid_width):
		for gy in range(board.grid_height):
			var c := Vector2i(gx, gy)
			if not (c in volley_cells):
				outside = c
				break
		if outside.x >= 0:
			break
	if outside.x < 0:
		push_error("CardActions: need a cell outside volley range")
		return false
	if volley.is_valid_release_cell(board, outside):
		push_error("CardActions: volley outside range must be invalid release")
		return false
	var charge_cells: Array[Vector2i] = charge.release_preview_cells(board)
	if charge_cells.is_empty() or not charge.is_valid_release_cell(board, charge_cells[0]):
		push_error("CardActions: charge rule cell must be valid")
		return false
	if charge.is_valid_release_cell(board, outside) and not (outside in charge_cells):
		push_error("CardActions: charge must reject non-preview cell")
		return false
	# 鼓舞：鼓手周围 1 外无效。
	var far := drum.cell + Vector2i(3, 3)
	if (
		far.x >= 0
		and far.x < board.grid_width
		and far.y >= 0
		and far.y < board.grid_height
		and inspire.is_valid_release_cell(board, far)
	):
		push_error("CardActions: inspire far cell must be invalid")
		return false
	if not inspire.is_valid_release_cell(board, drum.cell):
		push_error("CardActions: inspire drummer cell must be valid")
		return false
	# 鸣鼓：全盘有效。
	if not wardrum.is_valid_release_cell(board, Vector2i(0, 0)):
		push_error("CardActions: wardrum any board cell must be valid")
		return false
	# 恢复药水：施法者周围 attack_range 内有效，外无效。
	var potion_cells: Array[Vector2i] = potion.release_preview_cells(board)
	if potion_cells.is_empty() or not (healer.cell in potion_cells):
		push_error("CardActions: heal potion preview must include healer cell")
		return false
	if not potion.is_valid_release_cell(board, healer.cell):
		push_error("CardActions: heal potion caster cell must be valid")
		return false
	var potion_far := healer.cell + Vector2i(3, 3)
	if (
		potion_far.x >= 0
		and potion_far.x < board.grid_width
		and potion_far.y >= 0
		and potion_far.y < board.grid_height
		and potion.is_valid_release_cell(board, potion_far)
	):
		push_error("CardActions: heal potion far cell must be invalid")
		return false
	# 通用攻击卡不走规则格判定。
	var attack := TacticalActionCardScript.make_attack()
	if attack.is_valid_release_cell(board, Vector2i(0, 0)):
		push_error("CardActions: attack must not use skill release cells")
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
	if not card.plays_on_board():
		push_error("CardActions: inspire must play free without unit drop")
		return false
	if card.find_bound_caster(board) != drum:
		push_error("CardActions: inspire caster must resolve to wardrum")
		return false
	# 落在任意存活单位上仍算有效松手区（自由打出）。
	if not card.can_drop_on(drum) or not card.can_drop_on(ally):
		push_error("CardActions: inspire free play accepts any living drop")
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
	var fx: Array = res.get("passive_fx", []) as Array
	var saw_frenzy_fx := false
	for ev in fx:
		if not (ev is Dictionary):
			continue
		var d: Dictionary = ev as Dictionary
		if str(d.get("text", "")) == "+1狂" and str(d.get("sync", "")) == "status_frenzy":
			saw_frenzy_fx = true
			break
	if not saw_frenzy_fx:
		push_error("CardActions: inspire should emit +1狂 status float fx")
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
	# 临时攻卡工具仍可用（游侠猎召不发放临攻卡；箭袋已删）。
	deck.add_ephemeral_attack_to_hand()
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


## 医师「恢复药水」：绑定 / 规则格 / 无效格 / 死亡 cull / 落点治疗。
func _test_heal_potion_skill() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var healer: TacticalUnitInstance = null
	var ally: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		if u.def.id == "healer":
			healer = u
		elif ally == null:
			ally = u
	if healer == null or ally == null:
		push_error("CardActions: need healer + ally for potion")
		return false
	var card := TacticalActionCardScript.make_skill_heal_potion("healer")
	if (
		card.kind != TacticalActionCardScript.Kind.SKILL_HEAL_POTION
		or not card.is_heal_potion_aim()
		or not card.is_active_skill()
		or not card.plays_on_board()
	):
		push_error("CardActions: heal potion must be bound aim skill")
		return false
	if card.find_bound_caster(board) != healer:
		push_error("CardActions: heal potion caster must resolve to healer")
		return false
	var preview: Array[Vector2i] = card.release_preview_cells(board)
	if preview.is_empty() or not (healer.cell in preview):
		push_error("CardActions: heal potion release must include caster cell")
		return false
	var range_max := healer.def.attack_range
	for c in preview:
		if GridMathScript.chebyshev(healer.cell, c) > range_max:
			push_error("CardActions: heal potion release beyond attack_range")
			return false
	var outside := healer.cell + Vector2i(range_max + 1, 0)
	if (
		outside.x < board.grid_width
		and card.is_valid_release_cell(board, outside)
	):
		push_error("CardActions: heal potion outside range must be invalid")
		return false
	# 死亡 cull：移 1 + 攻 1 + 药水 2。
	var rng := RandomNumberGenerator.new()
	rng.seed = 83
	var deck: TacticalCardDeck = TacticalCardDeckScript.new(rng)
	deck.build_from_living_player_units(board)
	var before_total := deck.total_cards()
	var before_potion := deck.count_kind(TacticalActionCardScript.Kind.SKILL_HEAL_POTION)
	var removed := deck.on_player_unit_died(healer)
	if removed != 4:
		push_error("CardActions: healer death should remove 4, got %d" % removed)
		return false
	if deck.total_cards() != before_total - 4:
		push_error("CardActions: healer death total mismatch")
		return false
	if deck.count_kind(TacticalActionCardScript.Kind.SKILL_HEAL_POTION) != before_potion - 2:
		push_error("CardActions: heal potion should cull by 2")
		return false
	# 医师仍存活（cull 不击杀）；摆位测治疗结算。
	healer.hp = healer.def.max_hp
	for u in board.living_units():
		if u == healer or u == ally:
			continue
		if u.cell == Vector2i(2, 2) or u.cell == Vector2i(3, 2):
			u.cell = Vector2i(0, 7) if u.faction == TacticalFactionScript.Id.PLAYER else Vector2i(9, 7)
	healer.cell = Vector2i(2, 2)
	ally.cell = Vector2i(3, 2)
	ally.hp = 1
	healer.hp = 2
	var target := Vector2i(3, 2)
	var res: Dictionary = board.apply_heal_potion(healer, target, 2, 1)
	if not res.get("ok", false):
		push_error("CardActions: heal potion apply failed")
		return false
	# 落点格上的 ally 与半径内的 healer 均应回血。
	if ally.hp != 3:
		push_error("CardActions: potion should heal ally +2, got %d" % ally.hp)
		return false
	if healer.hp != 4:
		push_error("CardActions: potion may heal caster in radius, got %d" % healer.hp)
		return false
	var fx: Array = res.get("passive_fx", []) as Array
	if fx.is_empty():
		push_error("CardActions: heal potion should emit passive_fx")
		return false
	# 非医师不可投。
	var bad := board.apply_heal_potion(ally, target, 2, 1)
	if bad.get("ok", false):
		push_error("CardActions: non-healer must not throw potion")
		return false
	return true
