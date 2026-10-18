# 方格棋盘 · 3D 斜俯视 · 2D 占位单位

> **已实现**（占位骨架）。数值见 `resources/map/board_config.tres`。

## 玩家能做什么

- 主菜单进入**对战沙盘**：中央浮起方格盘，深色背景。
- **拖拽**平移镜头、**滚轮**正交缩放。
- 棋盘为 **10×8**（默认）交错色块；各 1 个 **Sprite3D** 占位单位（蓝/红）。
- 玩家回合可**点选格子**（HUD 显示坐标）；尚无移动或战斗。
- **结束行动**仍走回合钟（见 [TURN_CLOCK.md](./TURN_CLOCK.md)）。

## 规则与技术

- **坐标**：整数方格 `(x, y)`，原点在盘心。
- **视角**：正交相机，相对水平面约 **45°** 仰角 + **45°** 偏航（War Chess / 战术战棋式斜俯视）。
- **单位表现**：Billboard `Sprite3D` 站在格心上方；正式美术后续替换纹理。
- **不做**：WFC、迷雾、六边格、单位移动、战斗演算。

## 验收（开发）

- Headless：`scripts/map/grid_board_test_runner.gd` 打印 `GRID_BOARD_OK`。
- 轻量：`bash tools/run_light_verify.sh`。
