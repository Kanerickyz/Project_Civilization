# 战术单位 · 五人首版

> **已实现**（轻量切片）。数据在 `resources/units/*.tres`，逻辑在 `scripts/units/`。

## 移动与攻击距离（切比雪夫）

| 显示名 | id | 移动距离 | 对手移力池 | 攻击距离 | 说明 |
|--------|-----|----------|------------|----------|------|
| 盾卫 | `knight` | 1 | — | 1 | 前排近战 |
| 游侠 | `archer` | 2 | — | 3 | 攻击距离 3、移动距离 2；远程 |
| 大剑 | `mini_pekka` | 1 | — | 1 | 慢速重击 |
| 鼓手 | `wardrum` | 2 | — | 1 | 支援机动 |
| 爆爆 | `boomling` | 1 | — | 2 | 生命 6、攻击 2；燃烧 |
| 狼骑兵 | `rider` | 2 | 2 | **1**（近战邻格） | 敌方编制；生命 10；高速近战；行为状态机见 [WOLF_CAVALRY_INTENT.md](./WOLF_CAVALRY_INTENT.md) |

- **移动距离** = `move_range`：一次移动的路径步数不得超过此值（8 邻接、绕开城墙、禁斜穿墙角；无城墙时等于切比雪夫距离，见 [GRID_BOARD.md](./GRID_BOARD.md)）。游侠为 **2**。
- **玩家无移力池**：移动只靠打出移动卡授权；**一张移动卡只走一次**（成功落子后清授权）。见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)。
- **对手移力池** = `move_budget`（为 0 时等同 `move_range`）：对手 AI 在池内可逐步移动。
- **攻击距离** = `attack_range`（切比雪夫）。游侠为 **3**；狼骑兵为 **1**（近战邻格，含斜向）。
- 玩家移/攻须把卡**拖到**己方单位。选定后：**绿** overlay = `move_range` 内可达空格；**红** overlay = 攻击距离 footprint。**玩家**普攻/加强攻可选红圈内**友方**为目标；**对手 AI** 仍只打敌方。
- **点选敌方狼骑兵**时同样显示绿/红行动格（移最多 2、攻距 1，含地形阻挡）；见 [WOLF_CAVALRY_INTENT.md](./WOLF_CAVALRY_INTENT.md)。

## 触发式战术能力

| 显示名 | 触发时机 | 效果 |
|--------|----------|------|
| 盾卫 | **受伤** | 自身攻击 +1（本场，可叠加） |
| 游侠 | **击杀** | 立刻往手牌加 1 张临时攻击卡（用完销毁、不进三库） |
| 大剑 | — | **无被动** |
| 鼓手 | **移动结束** | 2 格内其他角色攻击 +1、生命 +1（本场；生命抬上限并回等量） |
| 爆爆 | **死亡** | 所在格及周围格单位获得 3 层燃烧（见 [BURN_STATUS.md](./BURN_STATUS.md)） |

侧栏仅**只读**说明。伤害/击杀/移动结束/死亡走 `TacticalBoard` 挂接触发。主动技能卡见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)。

## 规则（与 TurnClock）

- 沙盘预置 5 蓝（盾卫/游侠/大剑/鼓手/爆爆）+ 6 红（均为狼骑兵 `rider`，各 10 血）；贴图用已迁入的 `assets/autochess/.../unit_boomling_*`；`Sprite2D` 站在格心；头顶常驻 `当前HP/上限 攻N`（有护甲时附 `甲N`；`effective_attack`，含 buff；显式 `ui_font`；`mouse_filter` 忽略以免挡点格）、受伤 `-N!` popup；敌方狼骑兵另有**下一意图**角标（色菱形 + 攻/移/血/加）；燃烧为色菱形 + `燃N`；**长按约 0.38s** 弹出纸卡信息（对照 autochess `RealtimeUnitInfoCard`：名/阵营/攻血移射/护甲/被动·主动；松手关闭；不与手牌长按冲突）；多格移动按寻路格序逐格 Tween；待机轻微上下浮动；攻击/受击/死亡带 Tween。
- **开战前部署**：先进部署阶段，拖己方到左半盘合法格；确认后再抽手牌与开战触发（见 [DEPLOYMENT.md](./DEPLOYMENT.md)）。
- **玩家行动段**抽手牌；打出移动/攻击/主动技卡后再点目标；点「结束行动」先弃剩余手牌 → 对手 AI **逐单位**串行动画 → 自动回到玩家（见 [COMBAT.md](./COMBAT.md)、[CARD_ACTIONS.md](./CARD_ACTIONS.md)）。
- 回到玩家段：清空移动/攻击卡授权后抽牌（玩家无段内攻次预算）；回到对手段：重置对手**移力池**与 `attacked_this_side_turn`。
- **未做**：商店、招募、CombatEventBus、召唤。

## 验收（开发）

- Headless：`scripts/units/tactical_units_test_runner.gd` → `TACTICAL_UNITS_OK`；`game_loop_test_runner.gd` → `GAME_LOOP_OK`
- 棋盘：`scripts/map/grid_board_test_runner.gd` → `GRID_BOARD_OK`
- 轻量：`bash tools/run_light_verify.sh`
