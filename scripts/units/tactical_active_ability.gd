class_name TacticalActiveAbility
extends Resource
## 战棋触发式战术能力（对齐 autochess 触发语义，非 CombatEventBus）。


enum TriggerKind {
	ON_SIDE_TURN_START,
	ON_SELF_HURT,
	ON_SELF_DEPLOY,
	ON_SELF_KILL,
	ON_SELF_MOVE_END,
	ON_SELF_DEATH,
	## 玩家攻击瞄准卡选定有效目标并成功结算后（普攻/加强/燃爆/万箭），由存活己方单位触发。
	ON_PLAYER_ATTACK_CARD,
	## 同阵营其他单位阵亡时，由仍存活的友方触发。
	ON_ALLY_DEATH,
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
@export var ally_hp_buff: int = 0
@export var ally_buff_radius: int = 2
## 受击等触发时：周围友方恢复当前 HP（不含自身；不抬上限）。
@export var ally_heal_on_trigger: int = 0
## 击杀时往玩家手牌加 1 张临时攻击卡（仅玩家击杀生效）。
@export var grant_ephemeral_attack_on_kill: bool = false
## 击杀时：周围友方各尝试攻击一次（各用自身攻距/攻；无合法敌则跳过）。
@export var ally_attack_on_kill: bool = false
## 玩家打出攻击牌时从牌库抽 N 张（需 board.player_deck）。
@export var draw_cards_on_trigger: int = 0
## 触发时对中心格及周围（切比雪夫 ≤ aoe_burn_radius）存活单位施加燃烧层数。
@export var aoe_burn_stacks: int = 0
@export var aoe_burn_radius: int = 1
