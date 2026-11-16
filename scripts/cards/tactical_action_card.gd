class_name TacticalActionCard
extends RefCounted
## 通用行动卡：移动或攻击许可（不绑定具体单位）。


enum Kind { MOVE, ATTACK }

var kind: Kind = Kind.MOVE


func _init(p_kind: Kind = Kind.MOVE) -> void:
	kind = p_kind


func is_valid() -> bool:
	return kind == Kind.MOVE or kind == Kind.ATTACK


func kind_label() -> String:
	if kind == Kind.ATTACK:
		return "攻击"
	return "移动"


func display_label() -> String:
	return kind_label()
