# 战术单位 · 四人首版

> **已实现**（轻量切片）。数据在 `resources/units/*.tres`，逻辑在 `scripts/units/`。

## 移动力池与攻击距离（切比雪夫）

| 显示名 | id | 单步最远 | 本段移力池 | 攻击距离 | 说明 |
|--------|-----|----------|------------|----------|------|
| 盾卫 | `knight` | 1 | 1 | 1 | 前排近战 |
| 游侠 | `archer` | 2 | 2 | 3 | 攻击距离 3、移动距离 2；远程 |
| 大剑 | `mini_pekka` | 1 | 1 | 1 | 慢速重击 |
| 鼓手 | `wardrum` | 2 | 2 | 1 | 支援机动 |
| 狼骑兵 | `rider` | 2 | 2 | 1 | 敌方编制；高速近战（无被动） |

- **单步最远 / 移动距离** = `move_range`：一次移动的路径步数不得超过此值（8 邻接、绕开城墙、禁斜穿墙角；无城墙时等于切比雪夫距离，见 [GRID_BOARD.md](./GRID_BOARD.md)）。游侠为 **2**。
- **移力池** = `move_budget`（为 0 时等同 `move_range`）：玩家**一张移动卡只走一次**（成功落子后清授权）；对手 AI 仍可在池内逐步移动。见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)。
- **攻击距离** = `attack_range`（切比雪夫）。游侠为 **3**。
- 玩家移/攻须把卡**拖到**己方单位。选定后：**绿** overlay = 剩余移力可达空格；**红** overlay = 攻击距离 footprint。**玩家**普攻/加强攻可选红圈内**友方**为目标；**对手 AI** 仍只打敌方。

## 触发式战术能力

| 显示名 | 触发时机 | 效果 |
|--------|----------|------|
| 盾卫 | **受伤** | 自身攻击 +1（本场，可叠加） |
| 游侠 | **击杀** | 立刻往手牌加 1 张临时攻击卡（用完销毁、不进三库） |
| 大剑 | — | **无被动** |
| 鼓手 | **移动结束** | 2 格内其他角色攻击 +1、生命 +1（本场；生命抬上限并回等量） |

侧栏仅**只读**说明。伤害/击杀/移动结束走 `TacticalBoard` 挂接触发。主动技能卡见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)。

## 规则（与 TurnClock）

- 沙盘预置 4 蓝（盾卫/游侠/大剑/鼓手）+ 5 红（均为狼骑兵 `rider`）；`Sprite2D` 站在格心；头顶 HP、受伤 `-N!` popup；多格移动按寻路格序逐格 Tween；待机轻微上下浮动；攻击/受击/死亡带 Tween。
- **玩家行动段**抽手牌；打出移动/攻击/主动技卡后再点目标；点「结束行动」先弃剩余手牌 → 对手 AI **逐单位**串行动画 → 自动回到玩家（见 [COMBAT.md](./COMBAT.md)、[CARD_ACTIONS.md](./CARD_ACTIONS.md)）。
- 回到某方行动段时重置该方**移力池**、**攻击标记**；回到玩家段再抽牌。
- **未做**：商店、招募、CombatEventBus、召唤。

## 验收（开发）

- Headless：`scripts/units/tactical_units_test_runner.gd` → `TACTICAL_UNITS_OK`；`game_loop_test_runner.gd` → `GAME_LOOP_OK`
- 棋盘：`scripts/map/grid_board_test_runner.gd` → `GRID_BOARD_OK`
- 轻量：`bash tools/run_light_verify.sh`
