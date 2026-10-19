# 战斗与胜负 · 基础循环

> **已实现**（完全切片）。普攻在 `scripts/units/tactical_combat.gd`，对手 AI 在 `tactical_enemy_ai.gd`。

## 普攻

- 选中己方单位后，**红圈**为以当前格为圆心的攻击距离 footprint；点圈内**敌方单位**发动普攻。
- **每单位每方行动段**最多普攻 1 次；与移力池、主动技次数独立。
- 伤害 = 当前 `effective_attack()`（含本场攻加成）。攻击前播放冲刺 Tween，受击/死亡与 HP popup 协调。

## 移动

- 每行动段有 **移力池**（见 [UNITS.md](./UNITS.md)）；可在池内分多步移动，每步消耗该步路径步数（绕开城墙；无城墙时等于切比雪夫距离）。
- **绿圈**仅显示在**剩余移力**下仍可达的空格。

## 胜负

- 某阵营全部单位 `hp <= 0` → 该方失败，对方胜利。
- 沙盘弹出简要结算，可返回主菜单。

## 对手 AI（最小）

- 玩家点「结束行动」后进入对手行动段；AI **按单位 id 排序**，每个红方单位依次：在移力池内能攻则攻（优先低 HP），否则逐步靠近最近蓝方（按绕墙后的路径距离）；每步移动/攻击 Tween **串行**播放，全部单位完成后自动结束行动，回合数 +1，回到玩家。
- 进入某方行动段时重置该方移力池、`attacked_this_side_turn` 等段内标记。

## 验收

- `scripts/units/game_loop_test_runner.gd` → `GAME_LOOP_OK`
- 与 `TURN_CLOCK.md`、`UNITS.md` 联调：`bash tools/run_verify_runners.sh`
