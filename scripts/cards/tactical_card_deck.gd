class_name TacticalCardDeck
extends RefCounted
## 玩家三库（牌库 / 手牌 / 弃牌）与 STS 式抽弃。
## 卡为通用「移动」「攻击」；数量 = 己方存活单位数各贡献 1 张。


signal changed

const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

var draw_count: int = 5
var draw_pile: Array[TacticalActionCard] = []
var hand: Array[TacticalActionCard] = []
var discard_pile: Array[TacticalActionCard] = []
## 本段已获移动授权的己方单位（对象作键）。
var move_authorized: Dictionary = {}

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
	_draw_pile_shuffled = false
	changed.emit()


## 按场上己方存活单位生成：每人贡献通用攻击卡 1 + 移动卡 1。绝不收录敌方。
func build_from_living_player_units(board: TacticalBoard) -> void:
	clear()
	if board == null:
		return
	var player_count := 0
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		player_count += 1
		draw_pile.append(TacticalActionCardScript.new(TacticalActionCard.Kind.ATTACK))
		draw_pile.append(TacticalActionCardScript.new(TacticalActionCard.Kind.MOVE))
	# 不变量：总牌数 = 己方存活 × 2，且不含单位绑定。
	if draw_pile.size() != player_count * 2:
		push_error(
			"TacticalCardDeck: build size %d != player_count*2 (%d)"
			% [draw_pile.size(), player_count * 2]
		)
	changed.emit()


func begin_player_turn() -> void:
	move_authorized.clear()
	draw_up_to(draw_count)


func end_player_turn() -> void:
	discard_hand()
	move_authorized.clear()


func discard_hand() -> void:
	if hand.is_empty():
		return
	for card in hand:
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


func play_hand_index(index: int) -> TacticalActionCard:
	if index < 0 or index >= hand.size():
		return null
	var card: TacticalActionCard = hand[index]
	hand.remove_at(index)
	discard_pile.append(card)
	changed.emit()
	return card


func authorize_move(unit: TacticalUnitInstance) -> bool:
	if unit == null or not unit.is_alive():
		return false
	if unit.faction != TacticalFactionScript.Id.PLAYER:
		return false
	move_authorized[unit] = true
	changed.emit()
	return true


func is_move_authorized(unit: TacticalUnitInstance) -> bool:
	if unit == null:
		return false
	return bool(move_authorized.get(unit, false))


## 己方单位阵亡：从三库各减 1 张移动 + 1 张攻击（优先手牌→牌库→弃牌）；并清除其移动授权。
## 敌方阵亡不应调用；若误调且非玩家阵营则不改库。
func on_player_unit_died(unit: TacticalUnitInstance) -> int:
	if unit == null:
		return 0
	if unit.faction != TacticalFactionScript.Id.PLAYER:
		return 0
	var removed := 0
	removed += _remove_one_kind(TacticalActionCard.Kind.MOVE)
	removed += _remove_one_kind(TacticalActionCard.Kind.ATTACK)
	if move_authorized.has(unit):
		move_authorized.erase(unit)
	if removed > 0:
		changed.emit()
	return removed


## 兼容旧名：仅对己方单位生效，等价 on_player_unit_died。
func remove_unit_cards(unit: TacticalUnitInstance) -> int:
	return on_player_unit_died(unit)


func _remove_one_kind(kind: TacticalActionCard.Kind) -> int:
	if _remove_one_kind_from(hand, kind):
		return 1
	if _remove_one_kind_from(draw_pile, kind):
		return 1
	if _remove_one_kind_from(discard_pile, kind):
		return 1
	return 0


func _remove_one_kind_from(pile: Array[TacticalActionCard], kind: TacticalActionCard.Kind) -> bool:
	for i in range(pile.size() - 1, -1, -1):
		if pile[i].kind == kind:
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
