class_name TacticalUnitInstance
extends RefCounted

var def: TacticalUnitDef
var faction: TacticalFaction.Id = TacticalFaction.Id.PLAYER
var cell: Vector2i = Vector2i.ZERO
var hp: int = 1
var atk_bonus: int = 0
## 本场生命上限加成（如鼓手攻击牌周围 buff）。
var max_hp_bonus: int = 0
var moved_this_side_turn: bool = false
var remaining_move_budget: int = 0
var attacked_this_side_turn: bool = false
var deploy_trigger_fired: bool = false
## 燃烧层数：每方行动段开始时先造成=层数伤害，再减 1 层。
var burn_stacks: int = 0
## 狂暴层数：战局内永久；叠层上限 15；每层伤害 ×1.2（向上取整）。
var frenzy_stacks: int = 0
## 护甲：伤害先打护甲；溢出不穿血（见 apply_damage）。
var armor: int = 0
## 己方阵亡清牌是否已执行（幂等：段开始燃烧扫尸体不可重复减攻）。
var death_cards_culled: bool = false
## 敌方狼骑兵下一回合意图（TacticalEnemyAi.Intent；开战各自随机初相）。
var next_intent: int = 0
## 隐身：敌方不可选为目标；攻击/受伤/加状态取消。
var stealthed: bool = false

const FRENZY_MAX_STACKS := 15
const FRENZY_DAMAGE_MULT := 1.2
const _RIDER_ID := "rider"


func _init(p_def: TacticalUnitDef, p_faction: TacticalFaction.Id, p_cell: Vector2i) -> void:
	def = p_def
	faction = p_faction
	cell = p_cell
	hp = p_def.max_hp
	remaining_move_budget = p_def.action_move_budget()
	stealthed = p_def != null and p_def.starts_stealthed
	# 敌方狼骑兵开战各自独立随机初相；其它单位不读此字段。
	if (
		p_faction == TacticalFaction.Id.OPPONENT
		and p_def != null
		and p_def.id == _RIDER_ID
	):
		next_intent = TacticalEnemyAi.roll_initial_intent()
	else:
		next_intent = 0


func is_stealthed() -> bool:
	return stealthed and is_alive()


## 取消隐身；返回是否刚从隐身变为可见。
func break_stealth() -> bool:
	if not stealthed:
		return false
	stealthed = false
	return true


func grant_stealth() -> void:
	if not is_alive():
		return
	stealthed = true


## 不含狂暴倍率的基础战斗力（攻 + 本场加成）。
func attack_power() -> int:
	return def.attack + atk_bonus


func effective_attack() -> int:
	return apply_frenzy_to_damage(attack_power())


func effective_max_hp() -> int:
	return def.max_hp + max_hp_bonus


func is_alive() -> bool:
	return hp > 0


## 恢复当前 HP，不抬上限；返回实际增加量。
func apply_heal(amount: int) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var before := hp
	hp = mini(effective_max_hp(), hp + amount)
	return hp - before


func add_armor(amount: int) -> void:
	if amount <= 0:
		return
	# 加状态取消隐身。
	break_stealth()
	armor += amount


func add_burn_stacks(amount: int) -> void:
	if amount <= 0:
		return
	break_stealth()
	burn_stacks += amount


## 叠加狂暴；返回实际新增层数（受上限截断）。
func add_frenzy_stacks(amount: int) -> int:
	if amount <= 0:
		return 0
	break_stealth()
	var before := frenzy_stacks
	frenzy_stacks = mini(FRENZY_MAX_STACKS, frenzy_stacks + amount)
	return frenzy_stacks - before


## 每层 ×1.2，向上取整；stacks≤0 原样返回。
func apply_frenzy_to_damage(base: int) -> int:
	if frenzy_stacks <= 0 or base <= 0:
		return base
	return ceili(float(base) * pow(FRENZY_DAMAGE_MULT, float(frenzy_stacks)))
