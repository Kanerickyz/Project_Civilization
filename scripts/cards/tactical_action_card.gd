class_name TacticalActionCard
extends RefCounted
## 行动卡：通用移/攻、角色主动技、击杀临时攻卡。


enum Kind {
	MOVE,
	ATTACK,
	SKILL_DRAW,
	SKILL_STRONG_ATTACK,
	SKILL_BURN_ATTACK,
	SKILL_ARMOR,
	SKILL_INSPIRE,
	SKILL_STEALTH,
	SKILL_VOLLEY,
	SKILL_CHARGE,
	SKILL_HEAL_POTION,
}

var kind: Kind = Kind.MOVE
## 绑角色 id（空=不绑）；鸣鼓换手/燃爆/鼓舞用于死亡 cull 归属；加强攻/护甲为空。
var bound_unit_id: String = ""
## 强攻卡额外伤害。
var attack_bonus_damage: int = 0
## 燃爆攻：命中后对目标格及周围施加的燃烧层数。
var aoe_burn_stacks: int = 0
## 护甲卡：给目标叠加的护甲值。
var armor_grant: int = 0
## 用完销毁、不进弃/库；仅可在手牌短暂存在。
var ephemeral: bool = false


func _init(
	p_kind: Kind = Kind.MOVE,
	p_bound_unit_id: String = "",
	p_attack_bonus_damage: int = 0,
	p_ephemeral: bool = false,
	p_aoe_burn_stacks: int = 0,
	p_armor_grant: int = 0
) -> void:
	kind = p_kind
	bound_unit_id = p_bound_unit_id
	attack_bonus_damage = p_attack_bonus_damage
	ephemeral = p_ephemeral
	aoe_burn_stacks = p_aoe_burn_stacks
	armor_grant = p_armor_grant


func is_valid() -> bool:
	match kind:
		Kind.MOVE, Kind.ATTACK, Kind.SKILL_DRAW, Kind.SKILL_STRONG_ATTACK, Kind.SKILL_BURN_ATTACK, Kind.SKILL_ARMOR, Kind.SKILL_INSPIRE, Kind.SKILL_STEALTH, Kind.SKILL_VOLLEY, Kind.SKILL_CHARGE, Kind.SKILL_HEAL_POTION:
			return true
		_:
			return false


func is_attack_aim() -> bool:
	return (
		kind == Kind.ATTACK
		or kind == Kind.SKILL_STRONG_ATTACK
		or kind == Kind.SKILL_BURN_ATTACK
		or kind == Kind.SKILL_VOLLEY
	)


func is_stealth_aim() -> bool:
	return kind == Kind.SKILL_STEALTH


func is_charge_aim() -> bool:
	return kind == Kind.SKILL_CHARGE


func is_heal_potion_aim() -> bool:
	return kind == Kind.SKILL_HEAL_POTION


func is_active_skill() -> bool:
	return (
		kind == Kind.SKILL_DRAW
		or kind == Kind.SKILL_STRONG_ATTACK
		or kind == Kind.SKILL_BURN_ATTACK
		or kind == Kind.SKILL_ARMOR
		or kind == Kind.SKILL_INSPIRE
		or kind == Kind.SKILL_STEALTH
		or kind == Kind.SKILL_VOLLEY
		or kind == Kind.SKILL_CHARGE
		or kind == Kind.SKILL_HEAL_POTION
	)


## 非通用（绑角色）主动技：松手棋盘/手牌区或短按即可打出，自动绑定施法者。
## 通用攻/加强攻/护甲仍须拖到己方单位选定持卡者。
func plays_on_board() -> bool:
	return is_active_skill() and bound_unit_id != ""


func kind_label() -> String:
	match kind:
		Kind.ATTACK:
			return "攻击"
		Kind.SKILL_DRAW:
			return "鸣鼓换手"
		Kind.SKILL_STRONG_ATTACK:
			return "加强攻击"
		Kind.SKILL_BURN_ATTACK:
			return "燃爆"
		Kind.SKILL_ARMOR:
			return "护甲"
		Kind.SKILL_INSPIRE:
			return "鼓舞"
		Kind.SKILL_STEALTH:
			return "隐身"
		Kind.SKILL_VOLLEY:
			return "万箭齐发"
		Kind.SKILL_CHARGE:
			return "冲撞"
		Kind.SKILL_HEAL_POTION:
			return "恢复药水"
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
			return "短按或拖到规则格打出：手牌全部进弃，再抽 5 张（自动绑定鼓手）。无效格松手回手。"
		Kind.SKILL_STRONG_ATTACK:
			return "拖到任意己方单位：选定攻击者，再点红圈内单位；本次攻击额外 +%d 伤害。" % attack_bonus_damage
		Kind.SKILL_BURN_ATTACK:
			return (
				"短按或拖到规则格打出（自动绑定爆爆）：再点红圈内单位普攻；对目标及其周围格施加 %d 层燃烧。无效格松手回手。"
				% maxi(1, aoe_burn_stacks)
			)
		Kind.SKILL_ARMOR:
			return "拖到任意己方单位：立刻 +%d 护甲（可叠加）。伤害先打护甲，溢出不穿血。" % maxi(1, armor_grant)
		Kind.SKILL_INSPIRE:
			return "短按或拖到规则格打出（自动绑定鼓手）：周围 1 格内其他友方各 +1 狂暴（战局永久，上限 15；每层伤害 ×1.2 向上取整）。无效格松手回手。"
		Kind.SKILL_STEALTH:
			return "短按或拖到规则格打出（自动绑定刺客）：再点任意存活单位，令其隐身（敌方不可选为目标；攻击/受伤/加状态取消）。无效格松手回手。"
		Kind.SKILL_VOLLEY:
			return (
				"短按或拖到规则格打出（自动绑定游侠）；松手落在红圈合法目标可立刻结算。对目标格及相对攻击方向垂直左右两格造成伤害。无效格松手回手。"
			)
		Kind.SKILL_CHARGE:
			return (
				"短按或拖到规则格打出（自动绑定盾卫）：再点方向格；朝该方向冲撞最多 3 格。"
				+ "路径单位（含友军）受当前攻击力伤害并撞开；遇不可走格则停在前一格且自身受 3 点伤害。无效格松手回手。"
			)
		Kind.SKILL_HEAL_POTION:
			return (
				"短按或拖到规则格打出（自动绑定医师）：再点落点格；恢复该格一格内（含落点）友方各 2 点血。"
				+ "规则格=医师周围攻击距离内全部格。无效格松手回手。"
			)
		_:
			return ""


func can_drop_on(unit: TacticalUnitInstance) -> bool:
	if plays_on_board():
		# 自由打出：落在任意存活单位上也算有效松手区。
		return unit != null and unit.is_alive()
	if unit == null or not unit.is_alive():
		return false
	if unit.faction != TacticalFaction.Id.PLAYER:
		return false
	if bound_unit_id == "":
		return true
	return unit.def != null and unit.def.id == bound_unit_id


## 拖牌时高亮的「可释放/技能规则」格（棋盘逻辑格）。board 须有 living_units / 尺寸。
func release_preview_cells(board: TacticalBoard) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if board == null or not plays_on_board():
		return out
	var caster := find_bound_caster(board)
	match kind:
		Kind.SKILL_DRAW:
			for gx in range(board.grid_width):
				for gy in range(board.grid_height):
					out.append(Vector2i(gx, gy))
		Kind.SKILL_INSPIRE:
			if caster == null:
				return out
			var radius := 1
			for gx in range(board.grid_width):
				for gy in range(board.grid_height):
					var cell := Vector2i(gx, gy)
					if GridMath.chebyshev(caster.cell, cell) <= radius:
						out.append(cell)
		Kind.SKILL_BURN_ATTACK, Kind.SKILL_VOLLEY:
			if caster == null:
				return out
			return board.attack_range_cells(caster)
		Kind.SKILL_CHARGE:
			if caster == null:
				return out
			return TacticalCombat.charge_preview_cells(board, caster.cell)
		Kind.SKILL_HEAL_POTION:
			if caster == null:
				return out
			var range_max := caster.def.attack_range if caster.def != null else 2
			for gx in range(board.grid_width):
				for gy in range(board.grid_height):
					var cell := Vector2i(gx, gy)
					if GridMath.chebyshev(caster.cell, cell) <= range_max:
						out.append(cell)
		Kind.SKILL_STEALTH:
			for u in board.living_units():
				if u != null and u.is_alive():
					out.append(u.cell)
		_:
			pass
	return out


## 拖放松手格是否落在该技规则格内；否则应回手、不进弃。
func is_valid_release_cell(board: TacticalBoard, cell: Vector2i) -> bool:
	if board == null or not plays_on_board():
		return false
	return cell in release_preview_cells(board)


## 绑角色主动技的存活施法者；找不到则 null。
func find_bound_caster(board: TacticalBoard) -> TacticalUnitInstance:
	if board == null or bound_unit_id == "":
		return null
	for u in board.living_units():
		if (
			u != null
			and u.is_alive()
			and u.faction == TacticalFaction.Id.PLAYER
			and u.def != null
			and u.def.id == bound_unit_id
		):
			return u
	return null


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


## 爆爆主动技：自由打出后自动绑定爆爆；攻击时对目标及周围施加燃烧。
static func make_skill_burn_attack(
	bound_id: String = "boomling", burn_stacks: int = 3
) -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_BURN_ATTACK, bound_id, 0, false, burn_stacks)


## 盾卫主动技：通用护甲卡，拖到任意己方立刻加护甲（默认 +2，可配置）。
static func make_skill_armor(amount: int = 2) -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_ARMOR, "", 0, false, 0, maxi(1, amount))


## 鼓手主动技「鼓舞」：自由打出后自动绑定鼓手；周围 1 格友方 +1 狂暴。
static func make_skill_inspire(bound_id: String = "wardrum") -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_INSPIRE, bound_id)


## 刺客主动技：自由打出后自动绑定刺客；再点目标单位令其隐身。
static func make_skill_stealth(bound_id: String = "assassin") -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_STEALTH, bound_id)


## 游侠主动技「万箭齐发」：自由打出后自动绑定游侠；目标格 + 攻击方向垂直左右两格受伤。
static func make_skill_volley(bound_id: String = "archer") -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_VOLLEY, bound_id)


## 盾卫主动技「冲撞」：自由打出后自动绑定盾卫；再点方向格冲撞最多 3 格。
static func make_skill_charge(bound_id: String = "knight") -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_CHARGE, bound_id)


## 医师主动技「恢复药水」：自由打出后自动绑定医师；再点落点格治疗周围友方。
static func make_skill_heal_potion(bound_id: String = "healer") -> TacticalActionCard:
	return TacticalActionCard.new(Kind.SKILL_HEAL_POTION, bound_id)
