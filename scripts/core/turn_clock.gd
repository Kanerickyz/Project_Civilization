class_name TurnClock
extends RefCounted
## 玩家与对手交替。对手行动结束后，回合数加一。


var turn: int = 1
var player_active: bool = true


func end_turn() -> void:
	player_active = not player_active
	if player_active:
		turn += 1


func side_label() -> String:
	if player_active:
		return "玩家行动"
	return "对手行动"


func status_text() -> String:
	return "第 %d 回合 · %s" % [turn, side_label()]
