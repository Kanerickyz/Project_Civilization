class_name TacticalFaction
extends RefCounted

enum Id { PLAYER = 0, OPPONENT = 1 }


static func label(side: Id) -> String:
	match side:
		Id.PLAYER:
			return "玩家"
		Id.OPPONENT:
			return "对手"
		_:
			return "?"
