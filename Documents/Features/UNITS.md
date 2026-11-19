# 战术单位 · 七人首版

> **已实现**（轻量切片）。数据在 `resources/units/*.tres`，逻辑在 `scripts/units/`。

## 移动与攻击距离（切比雪夫）

| 显示名 | id | 移动距离 | 对手移力池 | 攻击距离 | 说明 |
|--------|-----|----------|------------|----------|------|
| 盾卫 | `knight` | 2 | — | 1 | 前排近战；击退见 [ATTACK_KNOCKBACK.md](./ATTACK_KNOCKBACK.md)；主动冲撞见 [KNIGHT_CHARGE.md](./KNIGHT_CHARGE.md) |
| 游侠 | `archer` | 3 | — | **2–3**（`attack_range_min=1`） | 远程；不可打邻格（距离 ≤1） |
| 大剑 | `mini_pekka` | 2 | — | 1 | 慢速重击 |
| 鼓手 | `wardrum` | 3 | — | 1 | 支援机动 |
| 爆爆 | `boomling` | 2 | — | 2 | 生命 6、攻击 2；燃烧 |
| 刺客 | `assassin` | **4 瞬移** | — | 1 | 生命 4、攻击 2；隐身见 [ASSASSIN_STEALTH.md](./ASSASSIN_STEALTH.md) |
| 医师 | `healer` | 2 | — | 2 | 生命 4、攻击 0；共情被动 +「恢复药水」 |
| 狼骑兵 | `rider` | 2 | 2 | **1**（近战邻格） | 敌方编制；生命 10；高速近战；行为状态机见 [WOLF_CAVALRY_INTENT.md](./WOLF_CAVALRY_INTENT.md) |

- **移动距离** = `move_range`：一次移动的路径步数不得超过此值（8 邻接、绕开城墙、禁斜穿墙角；无城墙时等于切比雪夫距离，见 [GRID_BOARD.md](./GRID_BOARD.md)）。游侠为 **3**。
- **玩家移力池**：每行动段重置为 `move_range`（`action_move_budget()`）；**点选己方再点绿格**移动，可分步，总步数 ≤ 剩余移力。见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)。
- **对手移力池** = `move_budget`（为 0 时等同 `move_range`）：对手 AI 在池内可逐步移动。
- **攻击距离** = `attack_range`（切比雪夫上限）。**最小射程死区** = `attack_range_min`（默认 0）：距离 ≤ min 不可攻击。游侠 `attack_range_min=1` → 只能打 **2…3**；狼骑兵为 **1**（近战邻格，含斜向）。
- 玩家**通用**攻/加强攻/护甲须把卡**拖到**己方单位；**非通用**主动技短按或拖棋盘即可（见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)）。选定后：**绿** overlay = `move_range` 内可达空格；**红** overlay = 攻击距离 footprint（含 min 死区）。**玩家**普攻/加强攻可选红圈内**友方**为目标；**对手 AI** 仍只打敌方。
- **点选敌方狼骑兵**时显示绿/红行动格（移最多 2、攻距 1，含地形阻挡），并叠加**下回合意图虚影**（路径/目标/回血加攻提示）；见 [WOLF_CAVALRY_INTENT.md](./WOLF_CAVALRY_INTENT.md)。

## 触发式战术能力

| 显示名 | 触发时机 | 效果 |
|--------|----------|------|
| 盾卫 | **友方死亡** | 从牌库抽 1 张 |
| 游侠 | — | **无被动**（主动技「万箭齐发」见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)） |
| 大剑 | — | **无被动** |
| 鼓手 | **打出攻击牌** | 周围 **1** 格其他友方攻击 +1、生命 +1（**本场**；生命抬上限并回等量） |
| 爆爆 | **死亡** | 所在格及周围格单位获得 3 层燃烧（见 [BURN_STATUS.md](./BURN_STATUS.md)） |
| 刺客 | **默认隐身** | 敌方不可选为目标；攻击/受伤/加状态取消（见 [ASSASSIN_STEALTH.md](./ASSASSIN_STEALTH.md)） |
| 医师 | **自身实际扣血** | 周围 **1** 格其他友方各恢复 **1** 血（不含自身；不抬上限；飘字 `+N血`） |

侧栏仅**只读**说明。伤害/击杀/友方死亡/打出攻击牌/死亡走 `TacticalBoard` / 沙盘挂接触发。被动生效时沙盘头顶飘字反馈（加攻 `+N攻`、加血 `+N血`、抽牌 `+N牌`）。主动技能卡见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)。

## 狂暴（鼓舞）

- 鼓手主动「鼓舞」给周围 1 格**其他友方**各 +1 层狂暴（见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)）。
- **战局内永久**；叠层上限 **15**。
- 每层伤害 ×**1.2**（对基础攻+加强额外后，向上取整）；头顶角标 `狂N`。

## 规则（与 TurnClock）

- 沙盘预置 7 蓝（盾卫/游侠/大剑/鼓手/爆爆/刺客/医师）+ 6 红狼骑兵（开局右半盘）；刺客用 `unit_shinobi_*`；医师用 `unit_apothecary_*`；`Sprite2D` 站在格心；头顶常驻 `当前HP/上限 攻N`（有护甲时附 `甲N`；隐身附 `隐`；`effective_attack`，含 buff/狂暴；显式 `ui_font`；`mouse_filter` 忽略以免挡点格）、受伤 `-N!` popup；敌方狼骑兵另有**下一意图**角标（色菱形 + 攻/移/血/加）；燃烧为色菱形 + `燃N`；狂暴为色菱形 + `狂N`；**长按约 0.38s** 弹出纸卡信息（对照 autochess `RealtimeUnitInfoCard`：名/阵营/攻血移射/护甲/被动·主动；松手关闭；不与手牌长按冲突）；多格移动按寻路格序逐格 Tween（刺客瞬移为直达 hop）；待机轻微上下浮动；攻击/受击/死亡带 Tween；击杀另闪全屏红斜横带 + 被击杀单位精灵黑剪影冲击（锚死亡位、尺寸对齐棋盘单位；见 [COMBAT.md](./COMBAT.md)）。
- **开战前部署**：先进部署阶段，左半盘拖己方；敌方已在右半；确认后抽手牌（见 [DEPLOYMENT.md](./DEPLOYMENT.md)）。
- **胜负**：敌方全灭 → 胜利；己方全灭 → 失败。
- **玩家行动段**抽手牌；点选移动或打出攻击/主动技卡后再点目标；点「结束行动」或手牌打完自动结束 → 先弃剩余手牌 → 对手 AI **逐单位**串行动画 → 自动回到玩家（见 [COMBAT.md](./COMBAT.md)、[CARD_ACTIONS.md](./CARD_ACTIONS.md)）。
- 回到玩家段：重置己方移力池、清空攻击卡授权后抽牌（玩家无段内攻次预算）；回到对手段：重置对手**移力池**与 `attacked_this_side_turn`。
- **未做**：商店、招募、CombatEventBus、召唤。

## 验收（开发）

- Headless：`scripts/units/tactical_units_test_runner.gd` → `TACTICAL_UNITS_OK`；`game_loop_test_runner.gd` → `GAME_LOOP_OK`
- 棋盘：`scripts/map/grid_board_test_runner.gd` → `GRID_BOARD_OK`
- 轻量：`bash tools/run_light_verify.sh`
