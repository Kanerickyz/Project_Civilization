class_name TacticalActiveAbility
extends Resource
## 战棋触发式战术能力（对齐 autochess 触发语义，非 CombatEventBus）。


enum TriggerKind {
	ON_SIDE_TURN_START,
	ON_SELF_HURT,
	ON_SELF_DEPLOY,
	ON_SELF_KILL,
}


@export var id: String = ""
@export var display_name: String = ""
@export var autochess_ability_id: String = ""
@export_multiline var rules_hint: String = ""

@export var trigger_kind: TriggerKind = TriggerKind.ON_SELF_HURT
@export var range_chebyshev: int = 1
@export var self_atk_on_trigger: int = 0
@export var self_atk_on_kill: int = 0
@export var ally_atk_buff: int = 0
@export var ally_buff_radius: int = 2
