class_name TacticalActionCard
extends RefCounted
## 玩家行动卡：绑定场上某一己方单位的移动或攻击许可。


enum Kind { MOVE, ATTACK }

var kind: Kind = Kind.MOVE
var unit: TacticalUnitInstance


func _init(p_kind: Kind = Kind.MOVE, p_unit: TacticalUnitInstance = null) -> void:
	kind = p_kind
	unit = p_unit


func is_valid() -> bool:
	return unit != null and unit.is_alive()


func kind_label() -> String:
	if kind == Kind.ATTACK:
		return "攻击"
	return "移动"


func display_label() -> String:
	var name := unit.def.display_name if unit != null and unit.def != null else "?"
	return "%s·%s" % [name, kind_label()]
