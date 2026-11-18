class_name TacticalUnitDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var max_hp: int = 1
@export var attack: int = 1
@export var move_range: int = 1
## 对手 AI 本行动段移动力池；0 表示与 move_range 相同。玩家不使用移力池。
@export var move_budget: int = 0
@export var attack_range: int = 1
## 最小射程死区（切比雪夫）：距离 ≤ 此值不可攻击。默认 0=无死区（可攻邻格）。游侠为 1。
@export var attack_range_min: int = 0
@export var texture_blue: Texture2D
@export var texture_red: Texture2D
## 相对不透明内容高度的视觉倍率；1 = 内容高缩放 `unit_world_height`。用于剪纸角色身型对齐。
@export var visual_scale: float = 1.0
@export var triggered_ability: TacticalActiveAbility


func action_move_budget() -> int:
	return move_budget if move_budget > 0 else move_range


## 切比雪夫距离是否落在可攻击带（min 死区外、≤ max，且 >0）。
func is_chebyshev_in_attack_band(dist: int) -> bool:
	if dist <= 0:
		return false
	if dist <= attack_range_min:
		return false
	return dist <= attack_range
