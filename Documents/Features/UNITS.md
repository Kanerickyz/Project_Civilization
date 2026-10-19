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
- **本段移力池** = `move_budget`（为 0 时等同 `move_range`）：同一行动段内多次移动，每段消耗等于该步路径步数，耗尽后本段不可再移动。
- 选中己方单位时：**绿** overlay = 从当前格出发、在**剩余移力**内可达的空格；**红** overlay = 以当前格为圆心、`attack_range` 内的格（含空格，便于看射程）。点敌方单位可 **普攻**（每单位每段 1 次）。

## 触发式战术能力（autochess 意图 → 战棋）

| 显示名 | autochess 主技能 id | 触发时机 | 效果 |
|--------|---------------------|----------|------|
| 盾卫 | `hurt_gain_atk_small` | **受伤** | 自身攻击 +1（本场，可叠加） |
| 游侠 | `deploy_self_atk_small` | **入阵**（开战已在场，各触发一次） | 自身攻击 +1（本场） |
| 大剑 | `kill_gain_atk_mid` | **击杀** | 自身攻击 +2（本场，可叠加） |
| 鼓手 | `turn_start_nearby_atk_small` | **己方行动段开始** | 2 格内其他友方攻击 +1（本场） |

侧栏仅**只读**说明；无「释放技能」按钮。伤害/击杀走 `TacticalBoard.apply_damage` 以挂接触发。

## 规则（与 TurnClock）

- 沙盘预置 4 蓝 + 4 红镜像；Billboard `Sprite3D` 站在格心；头顶 HP、受伤 `-N!` popup；移动/攻击/受击/死亡带 Tween。
- **玩家行动段**可点选己方、在移力池内分多次移动、普攻 1 次；点「结束行动」→ 对手 AI **逐单位**串行动画 → 自动回到玩家（见 [COMBAT.md](./COMBAT.md)）。
- 回到某方行动段时重置该方**移力池**、**攻击标记**，并处理「行动段开始」类触发。
- **未做**：商店、招募、CombatEventBus、召唤。

## 验收（开发）

- Headless：`scripts/units/tactical_units_test_runner.gd` → `TACTICAL_UNITS_OK`；`game_loop_test_runner.gd` → `GAME_LOOP_OK`
- 棋盘：`scripts/map/grid_board_test_runner.gd` → `GRID_BOARD_OK`
- 轻量：`bash tools/run_light_verify.sh`
