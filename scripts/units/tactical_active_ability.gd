class_name TacticalActiveAbility
extends Resource
## 战棋主动技（对齐 autochess 意图，非 CombatEventBus）。


enum TargetKind {
	ENEMY_UNIT,
	SELF_CENTER_ALLIES,
}


@export var id: String = ""
@export var display_name: String = ""
@export var autochess_ability_id: String = ""
@export_multiline var rules_hint: String = ""

@export var target_kind: TargetKind = TargetKind.ENEMY_UNIT
@export var range_chebyshev: int = 1
@export var damage_add: int = 0
@export var self_atk_on_cast: int = 0
@export var self_atk_on_kill: int = 0
@export var ally_atk_buff: int = 0
@export var ally_buff_radius: int = 2
