extends SceneTree

const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalAbilitySystemScript := preload("res://scripts/units/tactical_ability_system.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalCombatScript := preload("res://scripts/units/tactical_combat.gd")
const TacticalCardDeckScript := preload("res://scripts/cards/tactical_card_deck.gd")
const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")


func _initialize() -> void:
	if not _test_roster_loads():
		quit(1)
		return
	if not _test_move_and_attack_ranges():
		quit(1)
		return
	if not _test_archer_min_attack_range():
		quit(1)
		return
	if not _test_archer_no_attack_card_draw_passive():
		quit(1)
		return
	if not _test_knight_ally_death_draws():
		quit(1)
		return
	if not _test_armor_absorbs_no_overflow_hp():
		quit(1)
		return
	if not _test_wardrum_attack_card_buff():
		quit(1)
		return
	if not _test_pekka_no_passive():
		quit(1)
		return
	if not _test_basic_attack_flag():
		quit(1)
		return
	if not _test_side_turn_resets_attack():
		quit(1)
		return
	if not _test_archer_move_distance_two():
		quit(1)
		return
	if not _test_deploy_place_and_swap():
		quit(1)
		return
	if not _test_knight_knockback_free():
		quit(1)
		return
	if not _test_knight_knockback_blocked_mult():
		quit(1)
		return
	if not _test_knight_knockback_collision():
		quit(1)
		return
	if not _test_universal_knockback_non_knight():
		quit(1)
		return
	if not _test_ranged_attack_no_knockback():
		quit(1)
		return
	if not _test_archer_volley_side_damage():
		quit(1)
		return
	if not _test_knight_charge_path_hit_and_wall():
		quit(1)
		return
	if not _test_healer_sympathy_on_hurt():
		quit(1)
		return
	print("TACTICAL_UNITS_OK")
	quit(0)


func _test_roster_loads() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(6, 6)
	# 6 友（含医师，不含刺客）+ 6 狼骑。
	if board.living_units().size() != 12:
		push_error("TacticalUnits: expected 12 units, got %d" % board.living_units().size())
		return false
	var riders := 0
	var boomling := 0
	var healer := 0
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT:
			if u.def.id != "rider":
				push_error("TacticalUnits: opponent should be rider, got %s" % u.def.id)
				return false
			if u.def.max_hp != 10 or u.hp != 10:
				push_error("TacticalUnits: rider should have 10 hp, got max=%d hp=%d" % [u.def.max_hp, u.hp])
				return false
			if u.def.move_range != 2 or u.def.attack_range != 1:
				push_error(
					"TacticalUnits: rider should be move2/atk1, got move=%d atk=%d"
					% [u.def.move_range, u.def.attack_range]
				)
				return false
			if u.cell.x < 3:
				push_error("TacticalUnits: enemy should start on right half, got %s" % str(u.cell))
				return false
			riders += 1
		elif u.faction == TacticalFactionScript.Id.PLAYER:
			if u.cell.x >= 3:
				push_error("TacticalUnits: player should start on left half, got %s" % str(u.cell))
				return false
			if u.def.id == "boomling":
				boomling += 1
				if u.def.move_range != 2 or u.def.attack_range != 2 or u.def.max_hp != 6:
					push_error("TacticalUnits: boomling stats mismatch")
					return false
			elif u.def.id == "assassin":
				push_error("TacticalUnits: assassin should be removed from roster")
				return false
			elif u.def.id == "healer":
				healer += 1
				if (
					u.def.max_hp != 4
					or u.def.attack != 0
					or u.def.move_range != 2
					or u.def.attack_range != 2
				):
					push_error("TacticalUnits: healer stats mismatch")
					return false
				var ab := u.def.triggered_ability
				if (
					ab == null
					or ab.trigger_kind != TacticalActiveAbility.TriggerKind.ON_SELF_HURT
					or ab.ally_heal_on_trigger != 1
				):
					push_error("TacticalUnits: healer sympathy passive mismatch")
					return false
			elif u.def.id == "devman":
				push_error("TacticalUnits: devman should be removed from roster")
				return false
	if riders != 6:
		push_error("TacticalUnits: expected 6 wolf cavalry, got %d" % riders)
		return false
	if boomling != 1:
		push_error("TacticalUnits: expected 1 boomling, got %d" % boomling)
		return false
	if healer != 1:
		push_error("TacticalUnits: expected 1 healer, got %d" % healer)
		return false
	return true


func _player_unit(board: TacticalBoard, id: String) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == id:
			return u
	return null


func _opponent_unit(board: TacticalBoard, id: String) -> TacticalUnitInstance:
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.OPPONENT and u.def.id == id:
			return u
	return null


## 把占用 cell 的其他存活单位挪开，保留 keep（不击杀）。
func _relocate_off_cell(
	board: TacticalBoard, cell: Vector2i, keep: TacticalUnitInstance = null
) -> void:
	for u in board.living_units():
		if u == keep or u.cell != cell:
			continue
		for gy in range(board.grid_height):
			for gx in range(board.grid_width):
				var dest := Vector2i(gx, gy)
				if dest == cell:
					continue
				if board.unit_at(dest) == null:
					u.cell = dest
					break
			if u.cell != cell:
				break


func _test_move_and_attack_ranges() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	if archer == null:
		return false
	var moves := board.reachable_move_cells(archer)
	if moves.is_empty():
		push_error("TacticalUnits: archer should have move options")
		return false
	for c in moves:
		if GridMathScript.chebyshev(archer.cell, c) > archer.def.action_move_budget():
			push_error("TacticalUnits: move cell beyond action move budget")
			return false
	var attacks := board.attack_range_cells(archer)
	if attacks.is_empty():
		push_error("TacticalUnits: archer should show attack footprint")
		return false
	for c in attacks:
		var dist := GridMathScript.chebyshev(archer.cell, c)
		if not archer.def.is_chebyshev_in_attack_band(dist):
			push_error("TacticalUnits: attack cell outside band dist=%d" % dist)
			return false
	archer.remaining_move_budget = 0
	if not board.reachable_move_cells(archer).is_empty():
		push_error("TacticalUnits: exhausted move budget should have no move overlay")
		return false
	return true


func _test_archer_min_attack_range() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	var foe := _opponent_unit(board, "rider")
	if archer == null or foe == null:
		return false
	if archer.def.attack_range_min != 1 or archer.def.attack_range != 3:
		push_error(
			"TacticalUnits: archer min/max range should be 1/3, got %d/%d"
			% [archer.def.attack_range_min, archer.def.attack_range]
		)
		return false
	_relocate_off_cell(board, Vector2i(1, 1), archer)
	_relocate_off_cell(board, Vector2i(2, 1), foe)
	_relocate_off_cell(board, Vector2i(3, 1), foe)
	archer.cell = Vector2i(1, 1)
	foe.cell = Vector2i(2, 1)
	foe.hp = 99
	var near := TacticalCombatScript.try_basic_attack(
		board, archer, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if near.get("ok", false):
		push_error("TacticalUnits: archer must not attack distance 1")
		return false
	_relocate_off_cell(board, Vector2i(3, 1), foe)
	foe.cell = Vector2i(3, 1)
	var mid := TacticalCombatScript.try_basic_attack(
		board, archer, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not mid.get("ok", false):
		push_error("TacticalUnits: archer should attack distance 2")
		return false
	var footprint := board.attack_range_cells(archer)
	for c in footprint:
		if GridMathScript.chebyshev(archer.cell, c) <= archer.def.attack_range_min:
			push_error("TacticalUnits: footprint must exclude min-range dead zone")
			return false
	return true


func _test_archer_no_attack_card_draw_passive() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var deck: TacticalCardDeck = TacticalCardDeckScript.new()
	board.player_deck = deck
	deck.build_from_living_player_units(board)
	deck.hand.clear()
	deck.discard_pile.clear()
	var archer := _player_unit(board, "archer")
	if archer == null:
		return false
	if archer.def.triggered_ability != null:
		push_error("TacticalUnits: archer should have no triggered passive")
		return false
	var hand_before := deck.hand.size()
	var draw_before := deck.draw_pile.size()
	var fx: Array = []
	var logs := TacticalAbilitySystemScript.process_player_attack_card_played(board, fx)
	for line in logs:
		if str(line).begins_with("游侠"):
			push_error("TacticalUnits: archer must not log on attack card, got %s" % [logs])
			return false
	for ev in fx:
		if ev is Dictionary and str((ev as Dictionary).get("text", "")).ends_with("牌"):
			# 游侠已无箭袋；若仍有抽牌飘字，不得挂在游侠格上。
			if (ev as Dictionary).get("cell", Vector2i(-1, -1)) == archer.cell:
				push_error("TacticalUnits: archer must not emit draw fx")
				return false
	if deck.hand.size() != hand_before:
		push_error("TacticalUnits: attack card must not draw via archer")
		return false
	if deck.draw_pile.size() != draw_before:
		push_error("TacticalUnits: archer must not consume draw pile")
		return false
	# 击杀也不发临时攻卡。
	var foe := _opponent_unit(board, "rider")
	if foe == null:
		return false
	foe.hp = 1
	var hand_mid := deck.hand.size()
	board.apply_damage(foe, 1, archer)
	if foe.is_alive():
		push_error("TacticalUnits: archer should kill weak foe")
		return false
	if deck.hand.size() != hand_mid:
		push_error("TacticalUnits: archer kill must not grant ephemeral attack")
		return false
	return true


func _test_knight_ally_death_draws() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var deck: TacticalCardDeck = TacticalCardDeckScript.new()
	board.player_deck = deck
	deck.build_from_living_player_units(board)
	deck.hand.clear()
	deck.discard_pile.clear()
	var knight := _player_unit(board, "knight")
	var ally := _player_unit(board, "mini_pekka")
	if knight == null or ally == null:
		return false
	if knight.def.triggered_ability == null or knight.def.triggered_ability.draw_cards_on_trigger != 1:
		push_error("TacticalUnits: knight passive should draw on ally death")
		return false
	var before_atk := knight.effective_attack()
	board.apply_damage(knight, 1, null)
	if knight.effective_attack() != before_atk:
		push_error("TacticalUnits: knight hurt must no longer +1 atk")
		return false
	var hand_before := deck.hand.size()
	ally.hp = 1
	board.apply_damage(ally, 1, null)
	if ally.is_alive():
		push_error("TacticalUnits: ally should die for knight draw test")
		return false
	if deck.hand.size() != hand_before + 1:
		push_error("TacticalUnits: knight should draw 1 on ally death")
		return false
	# 敌方死亡不抽。
	var foe := _opponent_unit(board, "rider")
	if foe == null:
		return false
	var hand_mid := deck.hand.size()
	foe.hp = 1
	board.apply_damage(foe, 1, null)
	if deck.hand.size() != hand_mid:
		push_error("TacticalUnits: enemy death must not trigger knight draw")
		return false
	return true


func _test_armor_absorbs_no_overflow_hp() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var unit := _player_unit(board, "archer")
	if unit == null:
		return false
	unit.add_armor(2)
	var hp_before := unit.hp
	var res := board.apply_damage(unit, 5, null)
	if not res.get("ok", false):
		push_error("TacticalUnits: armor absorb hit should ok")
		return false
	if int(res.get("armor_absorbed", -1)) != 2:
		push_error("TacticalUnits: should absorb existing armor")
		return false
	if int(res.get("hp_damage", -1)) != 0:
		push_error("TacticalUnits: overflow must not hit HP")
		return false
	if unit.armor != 0 or unit.hp != hp_before:
		push_error("TacticalUnits: armor zero, HP unchanged after overflow")
		return false
	unit.add_armor(3)
	hp_before = unit.hp
	res = board.apply_damage(unit, 2, null)
	if unit.armor != 1 or unit.hp != hp_before or int(res.get("hp_damage", -1)) != 0:
		push_error("TacticalUnits: partial armor hit should leave remainder")
		return false
	return true


func _test_wardrum_attack_card_buff() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var drum := _player_unit(board, "wardrum")
	var archer := _player_unit(board, "archer")
	if drum == null or archer == null:
		return false
	drum.cell = Vector2i(2, 2)
	archer.cell = Vector2i(3, 2)
	var before_atk := archer.atk_bonus
	var before_max := archer.effective_max_hp()
	var before_hp := archer.hp
	# 移动结束不再鼓阵。
	if not board.try_move(drum, Vector2i(2, 3)):
		push_error("TacticalUnits: wardrum move setup failed")
		return false
	if archer.atk_bonus != before_atk:
		push_error("TacticalUnits: wardrum move end must no longer buff")
		return false
	drum.cell = Vector2i(2, 2)
	archer.cell = Vector2i(3, 2)
	var fx: Array = []
	var logs := TacticalAbilitySystemScript.process_player_attack_card_played(board, fx)
	if logs.is_empty():
		push_error("TacticalUnits: wardrum attack-card buff should log")
		return false
	if archer.atk_bonus != before_atk + 1:
		push_error("TacticalUnits: wardrum attack card should +1 atk nearby")
		return false
	if archer.effective_max_hp() != before_max + 1 or archer.hp != before_hp + 1:
		push_error("TacticalUnits: wardrum attack card should +1 hp nearby")
		return false
	var fx_texts: PackedStringArray = []
	for ev in fx:
		if ev is Dictionary:
			fx_texts.append(str((ev as Dictionary).get("text", "")))
	if not ("+1攻" in fx_texts) or not ("+1血" in fx_texts):
		push_error("TacticalUnits: wardrum passive should emit +1攻/+1血 fx, got %s" % [fx_texts])
		return false
	# 半径 1：距离 2 不吃。
	var pekka := _player_unit(board, "mini_pekka")
	if pekka == null:
		return false
	pekka.cell = Vector2i(4, 2)
	var pekka_atk := pekka.atk_bonus
	TacticalAbilitySystemScript.process_player_attack_card_played(board)
	if pekka.atk_bonus != pekka_atk:
		push_error("TacticalUnits: wardrum buff radius is 1, dist 2 must miss")
		return false
	# 鼓手自身不吃。
	var drum_atk := drum.atk_bonus
	TacticalAbilitySystemScript.process_player_attack_card_played(board)
	if drum.atk_bonus != drum_atk:
		push_error("TacticalUnits: wardrum must not buff self")
		return false
	return true


func _test_pekka_no_passive() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var pekka := _player_unit(board, "mini_pekka")
	var foe := _opponent_unit(board, "rider")
	if pekka == null or foe == null:
		return false
	if pekka.def.triggered_ability != null:
		push_error("TacticalUnits: mini_pekka should have no passive")
		return false
	foe.hp = 1
	var before := pekka.effective_attack()
	board.apply_damage(foe, 1, pekka)
	if foe.is_alive():
		push_error("TacticalUnits: pekka should kill weak rider")
		return false
	if pekka.effective_attack() != before:
		push_error("TacticalUnits: pekka kill must not grant atk")
		return false
	return true


func _vacate_cell(board: TacticalBoard, cell: Vector2i) -> void:
	var u := board.unit_at(cell)
	if u != null:
		u.hp = 0


func _place_knight_melee_target(
	board: TacticalBoard, knight: TacticalUnitInstance, foe: TacticalUnitInstance
) -> void:
	# 邻格目标；目标格与击退落点清空，避免叠友军或误触受阻×1.2。
	var target := knight.cell + Vector2i(0, 1)
	_relocate_off_cell(board, target, foe)
	foe.cell = target
	_vacate_cell(board, foe.cell + Vector2i(0, 1))


func _test_basic_attack_flag() -> bool:
	# 玩家无段内攻次标记；对手 AI 仍每段最多 1 攻。
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "rider")
	if knight == null or foe == null:
		return false
	_place_knight_melee_target(board, knight, foe)
	foe.hp = 99
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"]:
		push_error("TacticalUnits: player basic attack should succeed")
		return false
	if knight.attacked_this_side_turn:
		push_error("TacticalUnits: player attack must not set attacked_this_side_turn")
		return false
	# 击退后目标离开邻格：再摆回以验证连攻。
	_place_knight_melee_target(board, knight, foe)
	var again := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not again["ok"]:
		push_error("TacticalUnits: player may attack again without side-turn flag")
		return false
	var ally := knight
	ally.cell = foe.cell + Vector2i(0, 1)
	var opp1 := TacticalCombatScript.try_basic_attack(
		board, foe, ally.cell, TacticalFactionScript.Id.OPPONENT
	)
	if not opp1["ok"] or not foe.attacked_this_side_turn:
		push_error("TacticalUnits: opponent attack should set flag")
		return false
	var opp2 := TacticalCombatScript.try_basic_attack(
		board, foe, ally.cell, TacticalFactionScript.Id.OPPONENT
	)
	if opp2["ok"]:
		push_error("TacticalUnits: opponent should not attack twice per side turn")
		return false
	return true


func _test_side_turn_resets_attack() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "rider")
	if knight == null or foe == null:
		return false
	knight.cell = foe.cell + Vector2i(0, 1)
	var res := TacticalCombatScript.try_basic_attack(
		board, foe, knight.cell, TacticalFactionScript.Id.OPPONENT
	)
	if not res["ok"] or not foe.attacked_this_side_turn:
		push_error("TacticalUnits: opponent first attack should succeed and set flag")
		return false
	board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
	if foe.attacked_this_side_turn:
		push_error("TacticalUnits: side turn reset should clear opponent attack flag")
		return false
	if not TacticalCombatScript.can_basic_attack(foe, TacticalFactionScript.Id.OPPONENT):
		push_error("TacticalUnits: opponent should attack again after side turn reset")
		return false
	return true


func _test_archer_move_distance_two() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	if archer == null:
		return false
	if archer.def.move_range != 3 or archer.def.action_move_budget() != 3:
		push_error(
			"TacticalUnits: archer move_range/budget should be 3, got %d/%d"
			% [archer.def.move_range, archer.def.action_move_budget()]
		)
		return false
	var far := archer.cell + Vector2i(4, 0)
	if board.is_passable(far) and board.unit_at(far) == null:
		if board.try_move(archer, far):
			push_error("TacticalUnits: archer must not move 4 with range 3")
			return false
	var mid := archer.cell + Vector2i(3, 0)
	if board.unit_at(mid) != null:
		mid = archer.cell + Vector2i(0, 3)
	if not board.try_move(archer, mid):
		push_error("TacticalUnits: archer should move distance 3")
		return false
	return true


func _test_deploy_place_and_swap() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(6, 6)
	# 左半可部署，右半不可。
	if board.is_player_deploy_cell(Vector2i(3, 0)):
		push_error("TacticalUnits: right-half must not be deploy zone")
		return false
	if not board.is_player_deploy_cell(Vector2i(0, 0)):
		push_error("TacticalUnits: left-half passable cell should be deploy zone")
		return false
	var players: Array[TacticalUnitInstance] = []
	var opponent: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER:
			players.append(u)
		elif opponent == null:
			opponent = u
	if players.size() < 2 or opponent == null:
		push_error("TacticalUnits: deploy test needs >=2 players and 1 opponent")
		return false
	var a := players[0]
	var b := players[1]
	var dest := Vector2i(0, 1)
	if board.unit_at(dest) != null:
		dest = Vector2i(0, 0)
		if board.unit_at(dest) != null:
			dest = Vector2i(0, 3)
	if not board.try_deploy_place(a, dest):
		push_error("TacticalUnits: deploy place to empty zone failed")
		return false
	if a.cell != dest:
		push_error("TacticalUnits: deploy place did not move unit")
		return false
	if board.try_deploy_place(a, opponent.cell):
		push_error("TacticalUnits: must not deploy onto opponent")
		return false
	var a_cell := a.cell
	var b_cell := b.cell
	if not board.try_deploy_place(a, b_cell):
		push_error("TacticalUnits: deploy swap with ally failed")
		return false
	if a.cell != b_cell or b.cell != a_cell:
		push_error("TacticalUnits: deploy swap cells wrong")
		return false
	return true


func _test_knight_knockback_free() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "rider")
	if knight == null or foe == null:
		return false
	_place_knight_melee_target(board, knight, foe)
	foe.hp = 99
	var from := foe.cell
	var expect_to := from + Vector2i(0, 1)
	var base := knight.effective_attack()
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"]:
		push_error("TacticalUnits: knockback free attack should ok")
		return false
	if int(res["damage"]) != base:
		push_error("TacticalUnits: free knockback must keep normal damage")
		return false
	if not res.get("knockback_moved", false) or foe.cell != expect_to:
		push_error("TacticalUnits: free knockback should move target 1 cell")
		return false
	if res.get("knockback_blocked", false):
		push_error("TacticalUnits: free path must not mark blocked")
		return false
	return true


func _test_knight_knockback_blocked_mult() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "rider")
	if knight == null or foe == null:
		return false
	knight.cell = Vector2i(1, 1)
	foe.cell = Vector2i(1, 0)
	foe.hp = 99
	# 向上打出地图外 → 受阻。
	var base := knight.effective_attack()
	var expect := int(ceili(float(base) * TacticalCombatScript.KNIGHT_KNOCKBACK_BLOCK_MULT))
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"] or not res.get("knockback_blocked", false):
		push_error("TacticalUnits: OOB knockback should block")
		return false
	if res.get("knockback_moved", false) or foe.cell != Vector2i(1, 0):
		push_error("TacticalUnits: blocked knockback must not move")
		return false
	if int(res["damage"]) != expect:
		push_error(
			"TacticalUnits: blocked dmg want %d got %d" % [expect, int(res["damage"])]
		)
		return false
	# 树林受阻。
	knight.cell = Vector2i(2, 2)
	foe.cell = Vector2i(3, 2)
	_vacate_cell(board, Vector2i(4, 2))
	board.set_terrain_cells({Vector2i(4, 2): &"forest"})
	base = knight.effective_attack()
	expect = int(ceili(float(base) * TacticalCombatScript.KNIGHT_KNOCKBACK_BLOCK_MULT))
	var hp_before := foe.hp
	res = TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res.get("knockback_blocked", false) or foe.cell != Vector2i(3, 2):
		push_error("TacticalUnits: forest knockback should block without move")
		return false
	if int(res["damage"]) != expect or foe.hp != hp_before - expect:
		push_error("TacticalUnits: forest block should deal ceil(final*1.2)")
		return false
	return true


func _test_knight_knockback_collision() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "rider")
	var archer := _player_unit(board, "archer")
	if knight == null or foe == null or archer == null:
		return false
	knight.cell = Vector2i(2, 2)
	foe.cell = Vector2i(3, 2)
	archer.cell = Vector2i(4, 2)
	foe.hp = 99
	archer.hp = 99
	var base := knight.effective_attack()
	var expect := int(ceili(float(base) * TacticalCombatScript.KNIGHT_KNOCKBACK_BLOCK_MULT))
	var archer_before := archer.hp
	var res := TacticalCombatScript.try_basic_attack(
		board, knight, foe.cell, TacticalFactionScript.Id.PLAYER, true
	)
	if not res.get("knockback_blocked", false) or res.get("knockback_moved", false):
		push_error("TacticalUnits: occupied knock landing must block")
		return false
	if int(res["damage"]) != expect:
		push_error("TacticalUnits: occupied landing should use ×1.2 damage")
		return false
	if int(res.get("collision_damage", 0)) != 1 or archer.hp != archer_before - 1:
		push_error("TacticalUnits: collision should deal +1 to occupant")
		return false
	if res.get("collision_target") != archer:
		push_error("TacticalUnits: collision target should be archer")
		return false
	return true


func _test_universal_knockback_non_knight() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var pekka := _player_unit(board, "mini_pekka")
	var foe := _opponent_unit(board, "rider")
	if pekka == null or foe == null:
		return false
	pekka.cell = Vector2i(2, 2)
	foe.cell = Vector2i(3, 2)
	_vacate_cell(board, Vector2i(4, 2))
	foe.hp = 99
	var expect_to := Vector2i(4, 2)
	var res := TacticalCombatScript.try_basic_attack(
		board, pekka, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"] or not res.get("knockback_moved", false) or foe.cell != expect_to:
		push_error("TacticalUnits: melee non-knight attack should knockback 1")
		return false
	# 敌方近战攻击同样击退。
	var rider := foe
	var ally := _player_unit(board, "wardrum")
	if ally == null:
		return false
	rider.cell = Vector2i(5, 5)
	ally.cell = Vector2i(5, 4)
	_vacate_cell(board, Vector2i(5, 3))
	ally.hp = 99
	rider.attacked_this_side_turn = false
	var res2 := TacticalCombatScript.try_basic_attack(
		board, rider, ally.cell, TacticalFactionScript.Id.OPPONENT
	)
	if not res2["ok"] or not res2.get("knockback_moved", false) or ally.cell != Vector2i(5, 3):
		push_error("TacticalUnits: enemy melee attack should knockback too")
		return false
	# 爆爆邻格仍算近战击退。
	var boom := _player_unit(board, "boomling")
	if boom == null:
		return false
	boom.cell = Vector2i(1, 1)
	foe.cell = Vector2i(2, 1)
	_vacate_cell(board, Vector2i(3, 1))
	foe.hp = 99
	var res3 := TacticalCombatScript.try_basic_attack(
		board, boom, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res3["ok"] or not res3.get("knockback_moved", false) or foe.cell != Vector2i(3, 1):
		push_error("TacticalUnits: boomling adjacent attack should knockback")
		return false
	return true


func _test_ranged_attack_no_knockback() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	var boom := _player_unit(board, "boomling")
	var foe := _opponent_unit(board, "rider")
	if archer == null or boom == null or foe == null:
		return false
	board.set_terrain_cells({})
	# 游侠距离 2：远程，不击退、无×1.2。
	archer.cell = Vector2i(2, 2)
	foe.cell = Vector2i(4, 2)
	_vacate_cell(board, Vector2i(5, 2))
	foe.hp = 99
	var base := archer.effective_attack()
	var mid_cell := foe.cell
	var res := TacticalCombatScript.try_basic_attack(
		board, archer, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res["ok"]:
		push_error("TacticalUnits: ranged archer attack should ok")
		return false
	if res.get("knockback_moved", false) or res.get("knockback_blocked", false):
		push_error("TacticalUnits: ranged archer must not knockback")
		return false
	if foe.cell != mid_cell or int(res["damage"]) != base:
		push_error("TacticalUnits: ranged archer should keep cell and normal dmg")
		return false
	# 爆爆距离 2：远程，不击退。
	boom.cell = Vector2i(1, 1)
	foe.cell = Vector2i(3, 1)
	_vacate_cell(board, Vector2i(4, 1))
	foe.hp = 99
	var boom_base := boom.effective_attack()
	var foe_cell := foe.cell
	var res2 := TacticalCombatScript.try_basic_attack(
		board, boom, foe.cell, TacticalFactionScript.Id.PLAYER
	)
	if not res2["ok"] or res2.get("knockback_moved", false) or res2.get("knockback_blocked", false):
		push_error("TacticalUnits: boomling range-2 must not knockback")
		return false
	if foe.cell != foe_cell or int(res2["damage"]) != boom_base:
		push_error("TacticalUnits: boomling range-2 should keep cell and normal dmg")
		return false
	return true


func _test_archer_volley_side_damage() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var archer := _player_unit(board, "archer")
	var foe_mid := _opponent_unit(board, "rider")
	var foe_left: TacticalUnitInstance = null
	var foe_right: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.OPPONENT or u == foe_mid:
			continue
		if foe_left == null:
			foe_left = u
		elif foe_right == null:
			foe_right = u
			break
	if archer == null or foe_mid == null or foe_left == null or foe_right == null:
		push_error("TacticalUnits: volley needs archer + 3 foes")
		return false
	# 游侠在 (2,2) 打 (4,2)：方向 (1,0)，侧格 (4,1)/(4,3)。
	board.set_terrain_cells({})
	for keep_cell in [Vector2i(2, 2), Vector2i(4, 2), Vector2i(4, 1), Vector2i(4, 3), Vector2i(5, 2)]:
		_relocate_off_cell(board, keep_cell, null)
	archer.cell = Vector2i(2, 2)
	foe_mid.cell = Vector2i(4, 2)
	foe_left.cell = Vector2i(4, 1)
	foe_right.cell = Vector2i(4, 3)
	_vacate_cell(board, Vector2i(5, 2))
	foe_mid.hp = 99
	foe_left.hp = 99
	foe_right.hp = 99
	var splash := archer.effective_attack()
	var sides := TacticalCombatScript.volley_side_cells(archer.cell, foe_mid.cell)
	if sides.size() != 2 or not sides.has(Vector2i(4, 1)) or not sides.has(Vector2i(4, 3)):
		push_error("TacticalUnits: volley side cells wrong %s" % [sides])
		return false
	var res := TacticalCombatScript.try_basic_attack(
		board, archer, foe_mid.cell, TacticalFactionScript.Id.PLAYER, true, 0, 0, true
	)
	if not res["ok"]:
		push_error("TacticalUnits: volley primary should ok")
		return false
	if res.get("knockback_moved", false) or res.get("knockback_blocked", false):
		push_error("TacticalUnits: volley (ranged) must not knockback primary")
		return false
	if foe_mid.cell != Vector2i(4, 2):
		push_error("TacticalUnits: volley primary must stay put")
		return false
	var hits: Array = res.get("volley_hits", []) as Array
	if hits.size() != 2:
		push_error("TacticalUnits: volley should hit 2 sides, got %d" % hits.size())
		return false
	if foe_left.hp != 99 - splash or foe_right.hp != 99 - splash:
		push_error("TacticalUnits: volley side dmg want %d" % splash)
		return false
	# 无 volley 标志时不溅射。
	foe_left.hp = 99
	foe_right.hp = 99
	foe_mid.cell = Vector2i(4, 2)
	_vacate_cell(board, Vector2i(5, 2))
	var res2 := TacticalCombatScript.try_basic_attack(
		board, archer, foe_mid.cell, TacticalFactionScript.Id.PLAYER, true, 0, 0, false
	)
	if not res2["ok"] or (res2.get("volley_hits", []) as Array).size() != 0:
		push_error("TacticalUnits: normal attack must not volley")
		return false
	if foe_left.hp != 99 or foe_right.hp != 99:
		push_error("TacticalUnits: normal attack must not splash sides")
		return false
	if res2.get("knockback_moved", false) or foe_mid.cell != Vector2i(4, 2):
		push_error("TacticalUnits: ranged normal attack must not knockback")
		return false
	# 竖直攻击方向：游侠 (2,2)→(2,4)，侧格 (1,4)/(3,4)。
	for keep_cell_v in [Vector2i(2, 2), Vector2i(2, 4), Vector2i(1, 4), Vector2i(3, 4), Vector2i(2, 5)]:
		_relocate_off_cell(board, keep_cell_v, null)
	archer.cell = Vector2i(2, 2)
	foe_mid.cell = Vector2i(2, 4)
	foe_left.cell = Vector2i(1, 4)
	foe_right.cell = Vector2i(3, 4)
	_vacate_cell(board, Vector2i(2, 5))
	foe_mid.hp = 99
	foe_left.hp = 99
	foe_right.hp = 99
	var sides_v := TacticalCombatScript.volley_side_cells(archer.cell, foe_mid.cell)
	if (
		sides_v.size() != 2
		or not sides_v.has(Vector2i(1, 4))
		or not sides_v.has(Vector2i(3, 4))
	):
		push_error("TacticalUnits: vertical volley side cells wrong %s" % [sides_v])
		return false
	var res_v := TacticalCombatScript.try_basic_attack(
		board, archer, foe_mid.cell, TacticalFactionScript.Id.PLAYER, true, 0, 0, true
	)
	if not res_v["ok"] or (res_v.get("volley_hits", []) as Array).size() != 2:
		push_error("TacticalUnits: vertical volley should splash 2 sides")
		return false
	if foe_left.hp != 99 - splash or foe_right.hp != 99 - splash:
		push_error("TacticalUnits: vertical volley side dmg want %d" % splash)
		return false
	return true


func _test_knight_charge_path_hit_and_wall() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var knight := _player_unit(board, "knight")
	var foe := _opponent_unit(board, "rider")
	var ally := _player_unit(board, "archer")
	if knight == null or foe == null or ally == null:
		push_error("TacticalUnits: charge needs knight+foe+ally")
		return false
	board.set_terrain_cells({})
	# 全体先挪开，再摆冲撞轴（勿用 vacate 杀单位）。
	var park_i := 0
	for u in board.living_units():
		u.cell = Vector2i(park_i % 10, 7 if park_i < 10 else 6)
		park_i += 1
	knight.cell = Vector2i(1, 3)
	foe.cell = Vector2i(2, 3)
	ally.cell = Vector2i(3, 3)
	foe.hp = 99
	ally.hp = 99
	var atk := knight.effective_attack()
	var hp_before := knight.hp
	var res := TacticalCombatScript.try_knight_charge(board, knight, Vector2i(4, 3))
	if not res.get("ok", false):
		push_error("TacticalUnits: charge should ok")
		return false
	if knight.cell != Vector2i(4, 3):
		push_error("TacticalUnits: charge should end 3 steps at (4,3), got %s" % knight.cell)
		return false
	if foe.hp != 99 - atk or ally.hp != 99 - atk:
		push_error("TacticalUnits: charge path units should take effective_attack")
		return false
	var hits: Array = res.get("hits", []) as Array
	if hits.size() != 2:
		push_error("TacticalUnits: charge should hit foe+ally, got %d" % hits.size())
		return false
	if foe.cell == Vector2i(2, 3) or ally.cell == Vector2i(3, 3):
		push_error("TacticalUnits: charge should knock victims aside")
		return false
	# 撞墙：前方 2 格放树林 → 前进 1 格后停并自伤 3。
	board.set_terrain_cells({Vector2i(3, 3): &"forest"})
	park_i = 0
	for u in board.living_units():
		u.cell = Vector2i(park_i % 10, 7 if park_i < 10 else 6)
		park_i += 1
	knight.cell = Vector2i(1, 3)
	knight.hp = hp_before
	knight.armor = 0
	var res2 := TacticalCombatScript.try_knight_charge(board, knight, Vector2i(5, 3))
	if not res2.get("ok", false) or not res2.get("wall_stopped", false):
		push_error("TacticalUnits: charge into forest should wall-stop")
		return false
	if knight.cell != Vector2i(2, 3):
		push_error("TacticalUnits: wall charge should stop before forest at (2,3), got %s" % knight.cell)
		return false
	if int(res2.get("self_damage", 0)) != TacticalCombatScript.CHARGE_WALL_SELF_DAMAGE:
		push_error("TacticalUnits: wall self damage want 3")
		return false
	if knight.hp != hp_before - TacticalCombatScript.CHARGE_WALL_SELF_DAMAGE:
		push_error("TacticalUnits: knight should lose 3 hp on wall")
		return false
	# 非盾卫不可冲撞。
	ally.cell = Vector2i(1, 4)
	var bad := TacticalCombatScript.try_knight_charge(board, ally, Vector2i(5, 4))
	if bad.get("ok", false):
		push_error("TacticalUnits: non-knight must not charge")
		return false
	return true


## 医师共情：实际扣血时周围 1 格其他友方各恢复 1 血 + 绿飘字；不含自身；不抬上限。
func _test_healer_sympathy_on_hurt() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	var healer: TacticalUnitInstance = _player_unit(board, "healer")
	var ally_near: TacticalUnitInstance = _player_unit(board, "knight")
	var ally_far: TacticalUnitInstance = _player_unit(board, "archer")
	if healer == null or ally_near == null or ally_far == null:
		push_error("TacticalUnits: healer sympathy needs healer+knight+archer")
		return false
	healer.cell = Vector2i(2, 2)
	ally_near.cell = Vector2i(3, 2)
	ally_far.cell = Vector2i(5, 2)
	_relocate_off_cell(board, healer.cell, healer)
	_relocate_off_cell(board, ally_near.cell, ally_near)
	_relocate_off_cell(board, ally_far.cell, ally_far)
	healer.hp = healer.effective_max_hp()
	ally_near.hp = 1
	ally_far.hp = 1
	var near_before: int = ally_near.hp
	var far_before: int = ally_far.hp
	var self_before: int = healer.hp
	var res: Dictionary = board.apply_damage(healer, 1, null)
	if not res.get("ok", false) or int(res.get("hp_damage", 0)) != 1:
		push_error("TacticalUnits: healer should take 1 hp damage")
		return false
	if healer.hp != self_before - 1:
		push_error("TacticalUnits: healer must not self-heal from sympathy")
		return false
	if ally_near.hp != near_before + 1:
		push_error("TacticalUnits: neighbor ally should heal +1 from sympathy")
		return false
	if ally_far.hp != far_before:
		push_error("TacticalUnits: dist>1 ally must not heal from sympathy")
		return false
	var fx: Array = res.get("passive_fx", []) as Array
	var saw_heal_fx := false
	for ev in fx:
		if not (ev is Dictionary):
			continue
		var text := str((ev as Dictionary).get("text", ""))
		if text == "+1血":
			saw_heal_fx = true
			break
	if not saw_heal_fx:
		push_error("TacticalUnits: sympathy should emit +1血 fx, got %s" % [fx])
		return false
	# 满血友方不抬上限。
	ally_near.hp = ally_near.effective_max_hp()
	healer.hp = maxi(2, healer.hp)
	var full_before: int = ally_near.hp
	board.apply_damage(healer, 1, null)
	if ally_near.hp != full_before:
		push_error("TacticalUnits: sympathy must not raise max / overheal")
		return false
	# 仅护甲吸收不触发共情。
	ally_near.hp = 1
	healer.armor = 2
	healer.hp = healer.effective_max_hp()
	var armor_res: Dictionary = board.apply_damage(healer, 1, null)
	if int(armor_res.get("hp_damage", 0)) != 0:
		push_error("TacticalUnits: armor-only hit must not deal hp")
		return false
	if ally_near.hp != 1:
		push_error("TacticalUnits: armor-only hit must not trigger sympathy heal")
		return false
	return true
