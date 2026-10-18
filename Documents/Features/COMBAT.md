# 战斗与胜负 · 基础循环

> **已实现**（完全切片）。普攻在 `scripts/units/tactical_combat.gd`，对手 AI 在 `tactical_enemy_ai.gd`。

## 普攻

- 选中己方单位后，**红圈**为当前可普攻的敌方所在格（`attack_range` 切比雪夫）。
- **每单位每方行动段**最多普攻 1 次；与移动、主动技次数独立。
- 伤害 = 当前 `effective_attack()`（含本场攻加成）。

## 胜负

- 某阵营全部单位 `hp <= 0` → 该方失败，对方胜利。
- 沙盘弹出简要结算，可返回主菜单。

## 对手 AI（最小）

- 玩家点「结束行动」后进入对手行动段；AI 依次为各红方单位：能攻则攻（优先低 HP），否则向最近蓝方靠近一步。
- 对手段结束后 **自动** 结束行动，回合数 +1，回到玩家；双方该段移动/攻击/技能标记按 `TurnClock` 重置。

## 验收

- `scripts/units/game_loop_test_runner.gd` → `GAME_LOOP_OK`
- 与 `TURN_CLOCK.md`、`UNITS.md` 联调：`bash tools/run_verify_runners.sh`
