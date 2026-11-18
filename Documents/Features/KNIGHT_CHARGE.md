# 盾卫主动 · 冲撞

> **已实现**（轻量切片）。逻辑在 `scripts/units/tactical_combat.gd`（`try_knight_charge`）；卡面见 [CARD_ACTIONS.md](./CARD_ACTIONS.md)。

## 规则

- **仅盾卫**可打出主动卡「冲撞」（绑 `knight`，短按/拖棋盘自由打出）。
- 打出后点**方向格**：朝该方向（8 向单位步）冲撞最多 **3** 格。
- **路径上**每个有单位的格（含友军）：受盾卫**当前攻击力**（`effective_attack`）伤害，并**撞开**（优先垂直左右空可走格，否则沿冲撞方向）。
- 若 3 格内遇**不可走格**（地图外 / 树林等）：停在其**前一格**，盾卫自身受 **3** 点伤害（走护甲规则）。
- 不耗移力；不触发移动结束被动。位移表现走棋盘视图既有格间 Tween。

## 非目标

- 不改通用「护甲」卡；不改全员普攻击退数值。

## 验收

- 轻量：`bash tools/run_light_verify.sh`
- 相关：`scripts/units/tactical_units_test_runner.gd`、`scripts/cards/card_actions_test_runner.gd`
