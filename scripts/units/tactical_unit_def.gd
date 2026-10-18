class_name TacticalUnitDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var max_hp: int = 1
@export var attack: int = 1
@export var move_range: int = 1
## 本行动段移动力池；0 表示与 move_range 相同。
@export var move_budget: int = 0
@export var attack_range: int = 1
@export var texture_blue: Texture2D
@export var texture_red: Texture2D
@export var triggered_ability: TacticalActiveAbility


func action_move_budget() -> int:
	return move_budget if move_budget > 0 else move_range
