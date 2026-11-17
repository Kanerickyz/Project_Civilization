class_name TacticalUnitInstance
extends RefCounted

var def: TacticalUnitDef
var faction: TacticalFaction.Id = TacticalFaction.Id.PLAYER
var cell: Vector2i = Vector2i.ZERO
var hp: int = 1
var atk_bonus: int = 0
## 本场生命上限加成（如鼓手移动结束 buff）。
var max_hp_bonus: int = 0
var moved_this_side_turn: bool = false
var remaining_move_budget: int = 0
var attacked_this_side_turn: bool = false
var deploy_trigger_fired: bool = false
## 燃烧层数：每方行动段开始时先造成=层数伤害，再减 1 层。
var burn_stacks: int = 0
## 护甲：伤害先打护甲；溢出不穿血（见 apply_damage）。
var armor: int = 0


func _init(p_def: TacticalUnitDef, p_faction: TacticalFaction.Id, p_cell: Vector2i) -> void:
	def = p_def
	faction = p_faction
	cell = p_cell
	hp = p_def.max_hp
	remaining_move_budget = p_def.action_move_budget()


func effective_attack() -> int:
	return def.attack + atk_bonus


func effective_max_hp() -> int:
	return def.max_hp + max_hp_bonus


func is_alive() -> bool:
	return hp > 0


func add_armor(amount: int) -> void:
	if amount <= 0:
		return
	armor += amount


func add_burn_stacks(amount: int) -> void:
	if amount <= 0:
		return
	burn_stacks += amount
