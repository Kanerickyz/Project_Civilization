class_name TacticalActionCard
extends RefCounted
## 行动卡：通用移/攻、角色主动技、击杀临时攻卡。


enum Kind {
	MOVE,
	ATTACK,
	SKILL_DRAW,
	SKILL_STRONG_ATTACK,
}

var kind: Kind = Kind.MOVE
## 绑角色 id（空=不绑）；鸣鼓换手用于死亡 cull 归属；加强攻为空。
var bound_unit_id: String = ""
## 强攻卡额外伤害。
var attack_bonus_damage: int = 0
## 用完销毁、不进弃/库；仅可在手牌短暂存在。
var ephemeral: bool = false


func _init(
	p_kind: Kind = Kind.MOVE,
	p_bound_unit_id: String = "",
	p_attack_bonus_damage: int = 0,
	p_ephemeral: bool = false
) -> void:
	kind = p_kind
	bound_unit_id = p_bound_unit_id
	attack_bonus_damage = p_attack_bonus_damage
	ephemeral = p_ephemeral


func is_valid() -> bool:
	match kind:
		Kind.MOVE, Kind.ATTACK, Kind.SKILL_DRAW, Kind.SKILL_STRONG_ATTACK:
			return true
		_:
			return false


func is_attack_aim() -> bool:
	return kind == Kind.ATTACK or kind == Kind.SKILL_STRONG_ATTACK


func is_active_skill() -> bool:
	return kind == Kind.SKILL_DRAW or kind == Kind.SKILL_STRONG_ATTACK


## 松手在棋盘有效格即可打出（不要求落在单位上）。
func plays_on_board() -> bool:
	return kind == Kind.SKILL_DRAW


func kind_label() -> String:
	match kind:
		Kind.ATTACK:
			return "攻击"
		Kind.SKILL_DRAW:
			return "鸣鼓换手"
		Kind.SKILL_STRONG_ATTACK:
			return "加强攻击"
		_:
			return "移动"


func display_label() -> String:
	return kind_label()


func rules_detail() -> String:
	match kind:
		Kind.MOVE:
			return "拖到己方单位：重置其本段移力为满池并授权移动，再点绿格。可打多张再移。"
		Kind.ATTACK:
			return "拖到己方单位：选定攻击者，再点红圈内单位（含友方）普攻。可打多张再攻。"
		Kind.SKILL_DRAW:
			return "拖到棋盘任意有效格松手：手牌全部进弃，再抽 5 张。"
		Kind.SKILL_STRONG_ATTACK:
			return "拖到任意己方单位：选定攻击者，再点红圈内单位；本次攻击额外 +%d 伤害。" % attack_bonus_damage
		_:
			return ""


func can_drop_on(unit: TacticalUnitInstance) -> bool:
	if plays_on_board():
		# 棋盘打出；落在单位上也算有效区内。
		return unit != null and unit.is_alive()
	if unit == null or not unit.is_alive():
		return false
	if unit.faction != TacticalFaction.Id.PLAYER:
		return false
	if bound_unit_id == "":
		return true
	return unit.def != null and unit.def.id == bound_unit_id


static func make_move() -> TacticalActionCard:
	return TacticalActionCard.new(Kind.MOVE)


static func make_attack(ephemeral_card: bool = false) -> TacticalActionCard:
	return TacticalActionCard.new(Kind.ATTACK, "", 0, ephemeral_card)


## bound_id 仅作死亡 cull 归属；打出不要求拖到该角色。
static func make_skill_draw(bound_id: String = "wardrum") -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_DRAW, bound_id)


## 通用加强攻击：不绑角色，可拖到任意己方单位。
static func make_skill_strong_attack(bonus: int = 2) -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_STRONG_ATTACK, "", bonus)
