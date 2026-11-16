# 战术单位 · 四人首版

> **已实现**（轻量切片）。数据在 `resources/units/*.tres`，逻辑在 `scripts/units/`。

## 移动力池与攻击距离（切比雪夫）

| 显示名 | id | 单步最远 | 本段移力池 | 攻击距离 | 说明 |
|--------|-----|----------|------------|----------|------|
| 盾卫 | `knight` | 1 | 1 | 1 | 前排近战 |
| 游侠 | `archer` | 2 | 4 | 3 | 高机动远程，可分多段移动 |
| 大剑 | `mini_pekka` | 1 | 1 | 1 | 慢速重击 |
| 鼓手 | `wardrum` | 2 | 2 | 1 | 支援机动 |

- **单步最远** = `move_range`：一次移动的路径步数不得超过此值（8 邻接、绕开城墙、禁斜穿墙角；无城墙时等于切比雪夫距离，见 [GRID_BOARD.md](./GRID_BOARD.md)）。
- **本段移力池** = `move_budget`（为 0 时等同 `move_range`）：同一次「移动卡授权」内可分多步移动，每步消耗等于该步路径步数；耗尽后须再打一张移动卡才能再移（打出时**重置**该单位剩余移力为满池，见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)）。
- 玩家移/攻须把**通用**移动/攻击卡**拖到**己方单位。选定后：**绿** overlay = 剩余移力可达空格；**红** overlay = 攻击距离 footprint。**玩家**无每段移/攻次数上限（有卡即可再移/再攻）；**对手 AI** 仍按段内移力池与每单位每段 1 攻。

## 触发式战术能力（autochess 意图 → 战棋）

| 显示名 | autochess 主技能 id | 触发时机 | 效果 |
|--------|---------------------|----------|------|
| 盾卫 | `hurt_gain_atk_small` | **受伤** | 自身攻击 +1（本场，可叠加） |
| 游侠 | `deploy_self_atk_small` | **入阵**（开战已在场，各触发一次） | 自身攻击 +1（本场） |
| 大剑 | `kill_gain_atk_mid` | **击杀** | 自身攻击 +2（本场，可叠加） |
| 鼓手 | `turn_start_nearby_atk_small` | **己方行动段开始** | 2 格内其他友方攻击 +1（本场） |

侧栏仅**只读**说明；无「释放技能」按钮。伤害/击杀走 `TacticalBoard.apply_damage` 以挂接触发。

## 规则（与 TurnClock）

- 沙盘预置 4 蓝 + 4 红镜像；`Sprite2D` 站在格心；头顶 HP、受伤 `-N!` popup；待机轻微上下浮动（Tween 只改 `offset`，不挡格子点选与移动/冲刺/受击）；移动/攻击/受击/死亡带 Tween。
- **玩家行动段**抽手牌；打出移动/攻击卡后再点目标；点「结束行动」先弃剩余手牌 → 对手 AI **逐单位**串行动画 → 自动回到玩家（见 [COMBAT.md](./COMBAT.md)、[CARD_ACTIONS.md](./CARD_ACTIONS.md)）。
- 回到某方行动段时重置该方**移力池**、**攻击标记**，并处理「行动段开始」类触发；回到玩家段再抽牌。
- **未做**：商店、招募、CombatEventBus、召唤、主动技能卡。

## 验收（开发）

- Headless：`scripts/units/tactical_units_test_runner.gd` → `TACTICAL_UNITS_OK`；`game_loop_test_runner.gd` → `GAME_LOOP_OK`
- 棋盘：`scripts/map/grid_board_test_runner.gd` → `GRID_BOARD_OK`
- 轻量：`bash tools/run_light_verify.sh`
