class_name TacticalCardDeck
extends RefCounted
## 玩家三库（牌库 / 手牌 / 弃牌）与 STS 式抽弃。


signal changed

const TacticalActionCardScript := preload("res://scripts/cards/tactical_action_card.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

var draw_count: int = 5
var draw_pile: Array[TacticalActionCard] = []
var hand: Array[TacticalActionCard] = []
var discard_pile: Array[TacticalActionCard] = []
## 本段已打出移动卡授权的单位（对象作键）。
var move_authorized: Dictionary = {}

var _rng: RandomNumberGenerator
var _draw_pile_shuffled: bool = false


func _init(p_rng: RandomNumberGenerator = null) -> void:
	_rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		_rng.randomize()


func total_cards() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size()


func clear() -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	move_authorized.clear()
	_draw_pile_shuffled = false
	changed.emit()


## 按场上己方存活单位生成：每单位攻+移各 1。清空三库后写入牌库（未洗）。
func build_from_living_player_units(board: TacticalBoard) -> void:
	clear()
	if board == null:
		return
	for u in board.living_units():
		if u.faction != TacticalFactionScript.Id.PLAYER:
			continue
		draw_pile.append(TacticalActionCardScript.new(TacticalActionCard.Kind.ATTACK, u))
		draw_pile.append(TacticalActionCardScript.new(TacticalActionCard.Kind.MOVE, u))
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
	if card.kind == TacticalActionCard.Kind.MOVE and card.unit != null:
		move_authorized[card.unit] = true
	changed.emit()
	return card


func is_move_authorized(unit: TacticalUnitInstance) -> bool:
	if unit == null:
		return false
	return bool(move_authorized.get(unit, false))


## 阵亡立刻从三库剔除该单位对应卡，并清除其移动授权。
func remove_unit_cards(unit: TacticalUnitInstance) -> int:
	if unit == null:
		return 0
	var removed := 0
	removed += _purge_unit_from(hand, unit)
	removed += _purge_unit_from(draw_pile, unit)
	removed += _purge_unit_from(discard_pile, unit)
	if move_authorized.has(unit):
		move_authorized.erase(unit)
	if removed > 0:
		changed.emit()
	return removed


func _reshuffle_discard_into_draw() -> bool:
	if discard_pile.is_empty():
		return false
	for card in discard_pile:
		draw_pile.append(card)
	discard_pile.clear()
	_shuffle_array(draw_pile)
	return true


func _purge_unit_from(pile: Array[TacticalActionCard], unit: TacticalUnitInstance) -> int:
	var removed := 0
	var i := pile.size() - 1
	while i >= 0:
		var card: TacticalActionCard = pile[i]
		if card.unit == unit:
			pile.remove_at(i)
			removed += 1
		i -= 1
	return removed


func _shuffle_array(arr: Array[TacticalActionCard]) -> void:
	var n := arr.size()
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: TacticalActionCard = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
