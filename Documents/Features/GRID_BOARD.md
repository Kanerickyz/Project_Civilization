# 方格棋盘 · 2D 斜 45° 正交 · Sprite2D 单位

> **已实现**（占位骨架 + 地块类型）。数值见 `resources/map/board_config.tres`。

## 玩家能做什么

- 主菜单进入**对战沙盘**：中央方格盘。
- **拖拽**平移镜头、**滚轮**缩放（Camera2D）。
- 棋盘为 **8×8**（默认）草地格；第 4 行（y=3）示例城墙带 `01101101`；**4+4** 剪纸单位（见 [UNITS.md](./UNITS.md)）。
- 玩家回合可**点选己方单位**、按移动力移动、查看移动/攻击 overlay；可普攻、结束行动（对手 AI 段见 [COMBAT.md](./COMBAT.md)）。点城墙格提示「直城墙不可通行」。

## 地块

- 类型表 `resources/terrain/terrain_catalog.tres`：**空草地**（可通行）、**直城墙**（不可通行）。字段与 JSON 格式见 [MAP_EDITOR.md](./MAP_EDITOR.md)。
- 对战开局布局：`board_config.terrain_map_path`（默认 `res://resources/map/sandbox_battle_map.json`）。
- **移动与寻路**：8 邻接最短路，每步 1 移力；不可通行格不能进入或穿过；**禁止斜穿墙角**；路径中间的单位不挡路。
- 攻击距离仍按切比雪夫，城墙不挡射击。

## 表现

- **坐标**：逻辑格 `(x, y)` 先映射到地面 **XZ**（原点在盘心），再经 **`camera_pitch_deg` + `camera_yaw_deg`（默认各 45°）** 正交投影到 SubViewport 2D。
- **视角**：仍用 **Camera2D** 平移/缩放视口；投影公式与旧 3D 斜视正交一致，棋盘呈斜 45° 俯视（非顶视）。
- **地块绘制**（`Polygon2D`，投影四边形）：
  - 草地：方 footprint `cell_size × tile_inset`（默认 **0.98U**）；顶面色按 `(x+y)%2` **`#B4A158` / `#8F884C`**。
  - 直城墙：草地底同上；格内居中条形墙身（厚 **0.16U**、长 **inset**），石砖 **`#9C958C` / `#716C65`**；按相邻同类 **0° / 90°** 转向（与旧 3D 规则一致）。
- **3D 网格资源**：`resources/terrain/meshes/*.tres` 仍供 headless 尺寸/生成脚本使用，**运行时沙盘与地图编辑器不再实例化 MeshInstance3D**。
- **阴影**：**无 3D 方向光实时投影**。`BoardLook.shadow_*` 仍定义产品意图；2D 路径下单位使用 **脚下径向渐变软影**（`Sprite2D`），不随 Web 开关 3D 灯。若需强对比，可调 `unit_blob_opacity`。
- **BoardLook**：`background_color` 铺满 SubViewport 背板；`unit_modulate` 乘在角色 Sprite 上。已移除全屏后处理。
- **单位**：`Sprite2D`；高度 `unit_world_height`（默认 **0.88**）由纹理缩放；HP/伤害数字在 `CanvasLayer` 上跟随格心投影。
- **选中高亮**：格上半透明 `Polygon2D`——选中（蓝）、移动（绿）、攻击距离（红）。
- **不做**：WFC、迷雾、六边格。

## 验收（开发）

- Headless：`scripts/map/grid_board_test_runner.gd` → `GRID_BOARD_OK`（格坐标、2D 平移、棋盘色、墙条尺寸与转向、overlay、BoardLook 背景与脚下软影）。
- `scripts/units/terrain_movement_test_runner.gd` → `TERRAIN_MOVEMENT_OK`。
- 完全：`bash tools/run_verify_runners.sh`。