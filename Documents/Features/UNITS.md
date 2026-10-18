# 战术单位 · 四人首版

> **已实现**（轻量切片）。数据在 `resources/units/*.tres`，逻辑在 `scripts/units/`。

##  roster（autochess 意图 → 战棋主动技）

| 显示名 | id | 剪纸纹理 | autochess 主技能 id | 战棋主动技 |
|--------|-----|----------|---------------------|------------|
| 盾卫 | `knight` | `unit_shield_{blue,red}.png` | `hurt_gain_atk_small` | **铁壁强击**：邻格伤害，自身攻 +1（本场） |
| 游侠 | `archer` | `unit_archer_{blue,red}.png` | `deploy_self_atk_small` | **援军齐射**：3 格内伤害，自身攻 +1（本场） |
| 大剑 | `mini_pekka` | `unit_captain_{blue,red}.png` | `kill_gain_atk_mid` | **猎杀斩**：邻格伤害，击杀则自身攻 +2（本场） |
| 鼓手 | `wardrum` | `unit_wardrum_{blue,red}.png` | `turn_start_nearby_atk_small` | **前锋鸣鼓**：2 格内其他友方攻 +1（本场） |

## 规则（与 TurnClock）

- 沙盘预置 4 蓝 + 4 红镜像；Billboard `Sprite3D` 站在格心。
- **玩家行动段**可点选己方单位；**每单位每段行动**最多移动 1 次（`move_range` 切比雪夫 1）且最多释放主动技 1 次。
- 释放技能**不**自动结束行动；仍须点「结束行动」切换 `TurnClock`。
- 回到某方行动段时，重置该方单位的移动/技能次数标记。
- **未做**：商店、招募、CombatEventBus、召唤、正式普攻与胜负。

## 验收（开发）

- Headless：`scripts/units/tactical_units_test_runner.gd` → `TACTICAL_UNITS_OK`
- 棋盘：`scripts/map/grid_board_test_runner.gd` → `GRID_BOARD_OK`
- 轻量：`bash tools/run_light_verify.sh`
