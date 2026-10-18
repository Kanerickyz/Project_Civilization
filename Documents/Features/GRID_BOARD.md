# 方格棋盘 · 3D 斜俯视 · 2D 占位单位

> **已实现**（占位骨架）。数值见 `resources/map/board_config.tres`。

## 玩家能做什么

- 主菜单进入**对战沙盘**：中央浮起方格盘，深色背景。
- **拖拽**平移镜头、**滚轮**正交缩放。
- 棋盘为 **10×8**（默认）交错色块；**4+4** 剪纸单位（见 [UNITS.md](./UNITS.md)）。
- 玩家回合可**点选己方单位**、按移动力移动、查看移动/攻击 overlay；可普攻、结束行动（对手 AI 段见 [COMBAT.md](./COMBAT.md)）。

## 规则与技术

- **坐标**：整数方格 `(x, y)`，原点在盘心。
- **视角**：正交相机，相对水平面约 **45°** 仰角 + **45°** 偏航（War Chess / 战术战棋式斜俯视）。
- **单位表现**：Billboard `Sprite3D`；`unit_world_height`（默认 **0.88**）按纹理换算 `pixel_size`；正交 `camera_ortho_size` 约 **5.4**。
- **选中高亮**：格块混色表示选中（蓝）、移动（绿）、攻击距离（红）。
- **不做**：WFC、迷雾、六边格。

## 验收（开发）

- Headless：`scripts/map/grid_board_test_runner.gd` 打印 `GRID_BOARD_OK`。
- 轻量：`bash tools/run_light_verify.sh`。
