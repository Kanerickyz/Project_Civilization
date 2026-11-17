class_name TacticalCardDeck
extends RefCounted
## 玩家三库（牌库 / 手牌 / 弃牌）与 STS 式抽弃。
## 通用移/攻 + 存活角色主动技；游侠击杀临时攻卡仅进手、用完销毁。


signal changed

const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

const SKILL_STRONG_BONUS := 2

var draw_count: int = 5
var draw_pile: Array[TacticalActionCard] = []
var hand: Array[TacticalActionCard] = []
var discard_pile: Array[TacticalActionCard] = []
## 本段已获移动授权的己方单位（对象作键）。
var move_authorized: Dictionary = {}
## 本段攻击授权队列：单位 → Array[int]（每张攻击卡一次，值为该次额外伤害）。
## 同单位连拖多张攻击卡会入队多次，可连续结算多次攻击。
var attack_bonus_queues: Dictionary = {}
## 当前瞄准中下一次普攻额外伤害（队首）；无队列时为 0。
var pending_attack_bonus: int = 0

var _rng: RandomNumberGenerator
var _draw_pile_shuffled: bool = false


func _init(p_rng: RandomNumberGenerator = null) -> void:
	_rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		_rng.randomize()


func total_cards() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size()


func count_kind(kind: TacticalActionCard.Kind) -> int:
	return (
		_count_kind_in(hand, kind)
		+ _count_kind_in(draw_pile, kind)
		+ _count_kind_in(discard_pile, kind)
	)


func clear() -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	move_authorized.clear()
	attack_bonus_queues.clear()
	pending_attack_bonus = 0
	_draw_pile_shuffled = false
	changed.emit()


## 按场上己方存活：每人通用攻+移各 1；另按角色贡献主动技（游侠无）。绝不收录敌方。
func build_from_living_player_units(board: TacticalBoard) -> void:
	clear()
	if board == null:
		return
	var player_count := 0
	var skill_count := 0
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		player_count += 1
		draw_pile.append(TacticalActionCardScript.make_move())
		draw_pile.append(TacticalActionCardScript.make_attack())
		var skill := _skill_card_for_unit_id(u.def.id)
		if skill != null:
			draw_pile.append(skill)
			skill_count += 1
	var expected := player_count * 2 + skill_count
	if draw_pile.size() != expected:
		push_error(
			"TacticalCardDeck: build size %d != expected %d"
			% [draw_pile.size(), expected]
		)
	changed.emit()


func begin_player_turn() -> void:
	move_authorized.clear()
	attack_bonus_queues.clear()
	pending_attack_bonus = 0
	draw_up_to(draw_count)


func end_player_turn() -> void:
	discard_hand()
	move_authorized.clear()
	attack_bonus_queues.clear()
	pending_attack_bonus = 0


func discard_hand() -> void:
	if hand.is_empty():
		return
	var kept: Array[TacticalActionCard] = []
	for card in hand:
		if card.ephemeral:
			# 临时卡不进三库，直接销毁。
			continue
		kept.append(card)
	for card in kept:
		discard_pile.append(card)
	hand.clear()
	changed.emit()


func draw_up_to(count: int) -> int:
	var drawn := 0
	if not _draw_pile_shuffled:
		_shuffle_array(draw_pile)
		_draw_pile_shuffled = true
	while drawn < count:
		if draw_pile.is_empty():
			if not _reshuffle_discard_into_draw():
				break
		if draw_pile.is_empty():
			break
		hand.append(draw_pile.pop_back())
		drawn += 1
	if drawn > 0:
		changed.emit()
	return drawn


## 打出：非临时卡进弃；临时卡销毁。
func play_hand_index(index: int) -> TacticalActionCard:
	if index < 0 or index >= hand.size():
		return null
	var card: TacticalActionCard = hand[index]
	hand.remove_at(index)
	if not card.ephemeral:
		discard_pile.append(card)
	changed.emit()
	return card


## 游侠击杀：立刻往手牌加 1 张临时攻击卡（用完销毁、不进三库）。
func add_ephemeral_attack_to_hand() -> TacticalActionCard:
	var card := TacticalActionCardScript.make_attack(true)
	hand.append(card)
	changed.emit()
	return card


## 鼓手主动技：当前手牌（已打出的技卡已离手）全部进弃，再抽 draw_count。
func resolve_wardrum_redraw() -> int:
	discard_hand()
	return draw_up_to(draw_count)


## 打出移动卡并选定己方单位：授权本段移动一次（路径步数 ≤ move_range；无移力池）。
func authorize_move(unit: TacticalUnitInstance) -> bool:
	if unit == null or not unit.is_alive():
		return false
	if unit.faction != TacticalFactionScript.Id.PLAYER:
		return false
	move_authorized[unit] = true
	unit.remaining_move_budget = maxi(1, unit.def.move_range)
	unit.moved_this_side_turn = false
	changed.emit()
	return true


## 一次成功移动后消耗授权：清授权并清空本次移动额度（一张移动卡只走一次）。
func consume_move_authorization(unit: TacticalUnitInstance) -> void:
	if unit == null:
		return
	if move_authorized.has(unit):
		move_authorized.erase(unit)
	unit.remaining_move_budget = 0
	unit.moved_this_side_turn = true
	changed.emit()


## 打出攻击/加强攻击卡：入队一次攻击授权；加强攻的额外伤害随该次入队。
## 同单位可连拖多张，队列累加；不使用 attacked_this_side_turn（玩家无段内攻次预算）。
func authorize_attack(unit: TacticalUnitInstance, bonus_damage: int = 0) -> bool:
	if unit == null or not unit.is_alive():
		return false
	if unit.faction != TacticalFactionScript.Id.PLAYER:
		return false
	var q: Array = attack_bonus_queues.get(unit, [])
	q.append(maxi(0, bonus_damage))
	attack_bonus_queues[unit] = q
	_sync_pending_attack_bonus(unit)
	changed.emit()
	return true


## 兼容旧名：等同 authorize_attack。
func prepare_attack(unit: TacticalUnitInstance, bonus_damage: int = 0) -> bool:
	return authorize_attack(unit, bonus_damage)


## 一次成功攻击后消耗队首授权（一张攻击卡只结算一次）；若仍有余次则 pending 跟到下一次。
func consume_attack_authorization(unit: TacticalUnitInstance) -> int:
	var n := 0
	if unit != null and attack_bonus_queues.has(unit):
		var q: Array = attack_bonus_queues[unit]
		if not q.is_empty():
			n = int(q.pop_front())
		if q.is_empty():
			attack_bonus_queues.erase(unit)
		else:
			attack_bonus_queues[unit] = q
	_sync_pending_attack_bonus(unit)
	changed.emit()
	return n


## 取消瞄准：清空该单位全部攻击授权（已打牌不回手）。
func clear_attack_authorization(unit: TacticalUnitInstance) -> void:
	if unit != null and attack_bonus_queues.has(unit):
		attack_bonus_queues.erase(unit)
	_sync_pending_attack_bonus(unit)
	changed.emit()


func consume_pending_attack_bonus() -> int:
	var n := pending_attack_bonus
	pending_attack_bonus = 0
	return n


func attack_authorization_count(unit: TacticalUnitInstance) -> int:
	if unit == null or not attack_bonus_queues.has(unit):
		return 0
	return (attack_bonus_queues[unit] as Array).size()


func is_move_authorized(unit: TacticalUnitInstance) -> bool:
	if unit == null:
		return false
	return bool(move_authorized.get(unit, false))


func is_attack_authorized(unit: TacticalUnitInstance) -> bool:
	return attack_authorization_count(unit) > 0


func _sync_pending_attack_bonus(unit: TacticalUnitInstance) -> void:
	if unit != null and attack_bonus_queues.has(unit):
		var q: Array = attack_bonus_queues[unit]
		pending_attack_bonus = int(q[0]) if not q.is_empty() else 0
	else:
		pending_attack_bonus = 0


## 己方阵亡：减通用移/攻各 1；绑角色主动技按 owner 减 1；通用加强攻按贡献者减 1；清移/攻授权。
func on_player_unit_died(unit: TacticalUnitInstance) -> int:
	if unit == null:
		return 0
	if unit.faction != TacticalFactionScript.Id.PLAYER:
		return 0
	var removed := 0
	removed += _remove_one_kind(TacticalActionCard.Kind.MOVE)
	removed += _remove_one_kind(TacticalActionCard.Kind.ATTACK)
	var unit_id := unit.def.id if unit.def != null else ""
	var skill_kind := _skill_kind_for_unit_id(unit_id)
	if skill_kind == int(TacticalActionCard.Kind.SKILL_DRAW):
		removed += _remove_one_bound_skill(skill_kind, unit_id)
	elif skill_kind == int(TacticalActionCard.Kind.SKILL_STRONG_ATTACK):
		# 加强攻已解绑：按 kind 减 1（贡献者阵亡仍 cull 一张）。
		removed += _remove_one_skill_kind(skill_kind)
	var cleared_auth := false
	if move_authorized.has(unit):
		move_authorized.erase(unit)
		cleared_auth = true
	if attack_bonus_queues.has(unit):
		attack_bonus_queues.erase(unit)
		_sync_pending_attack_bonus(null)
		cleared_auth = true
	if removed > 0 or cleared_auth:
		changed.emit()
	return removed


func remove_unit_cards(unit: TacticalUnitInstance) -> int:
	return on_player_unit_died(unit)


static func expected_skill_count_for_board(board: TacticalBoard) -> int:
	if board == null:
		return 0
	var n := 0
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		if _skill_kind_for_unit_id(u.def.id) >= 0:
			n += 1
	return n


static func _skill_card_for_unit_id(unit_id: String) -> TacticalActionCard:
	match unit_id:
		"wardrum":
			return TacticalActionCardScript.make_skill_draw("wardrum")
		"knight", "mini_pekka":
			# 盾卫/大剑各贡献 1 张通用加强攻（不绑角色）。
			return TacticalActionCardScript.make_skill_strong_attack(SKILL_STRONG_BONUS)
		_:
			return null


static func _skill_kind_for_unit_id(unit_id: String) -> int:
	match unit_id:
		"wardrum":
			return int(TacticalActionCard.Kind.SKILL_DRAW)
		"knight", "mini_pekka":
			return int(TacticalActionCard.Kind.SKILL_STRONG_ATTACK)
		_:
			return -1


func _remove_one_kind(kind: TacticalActionCard.Kind) -> int:
	if _remove_one_kind_from(hand, kind):
		return 1
	if _remove_one_kind_from(draw_pile, kind):
		return 1
	if _remove_one_kind_from(discard_pile, kind):
		return 1
	return 0


func _remove_one_bound_skill(kind_i: int, bound_id: String) -> int:
	var kind := kind_i as TacticalActionCard.Kind
	if _remove_bound_from(hand, kind, bound_id):
		return 1
	if _remove_bound_from(draw_pile, kind, bound_id):
		return 1
	if _remove_bound_from(discard_pile, kind, bound_id):
		return 1
	return 0


## 按 kind 减 1 张主动技（不看 bound；用于通用加强攻 cull）。
func _remove_one_skill_kind(kind_i: int) -> int:
	var kind := kind_i as TacticalActionCard.Kind
	if _remove_skill_kind_from(hand, kind):
		return 1
	if _remove_skill_kind_from(draw_pile, kind):
		return 1
	if _remove_skill_kind_from(discard_pile, kind):
		return 1
	return 0


func _remove_skill_kind_from(pile: Array[TacticalActionCard], kind: TacticalActionCard.Kind) -> bool:
	for i in range(pile.size() - 1, -1, -1):
		var c: TacticalActionCard = pile[i]
		if c.kind == kind:
			pile.remove_at(i)
			return true
	return false


func _remove_one_kind_from(pile: Array[TacticalActionCard], kind: TacticalActionCard.Kind) -> bool:
	# 只减永久通用卡；临时攻卡与主动技不在此列。
	for i in range(pile.size() - 1, -1, -1):
		var c: TacticalActionCard = pile[i]
		if (
			c.kind == kind
			and not c.ephemeral
			and not c.is_active_skill()
			and c.bound_unit_id == ""
		):
			pile.remove_at(i)
			return true
	return false


func _remove_bound_from(
	pile: Array[TacticalActionCard], kind: TacticalActionCard.Kind, bound_id: String
) -> bool:
	for i in range(pile.size() - 1, -1, -1):
		var c: TacticalActionCard = pile[i]
		if c.kind == kind and c.bound_unit_id == bound_id:
			pile.remove_at(i)
			return true
	return false


func _count_kind_in(pile: Array[TacticalActionCard], kind: TacticalActionCard.Kind) -> int:
	var n := 0
	for c in pile:
		if c.kind == kind:
			n += 1
	return n


func _reshuffle_discard_into_draw() -> bool:
	if discard_pile.is_empty():
		return false
	for card in discard_pile:
		draw_pile.append(card)
	discard_pile.clear()
	_shuffle_array(draw_pile)
	return true


func _shuffle_array(arr: Array[TacticalActionCard]) -> void:
	var n := arr.size()
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: TacticalActionCard = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
