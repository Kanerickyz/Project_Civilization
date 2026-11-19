# 方格棋盘 · 2D 斜 45° 正交 · Sprite2D 单位

> **已实现**（占位骨架 + 地块类型）。数值见 `resources/map/board_config.tres`。

## 玩家能做什么

- 主菜单进入**对战沙盘**：中央方格盘。
- **拖拽**平移镜头、**滚轮**缩放（Camera2D）。
- 棋盘为 **6×6**（默认）；开局内部 seed **成簇**铺湖泊/树林（各 0%–15%，见 [LAKE_FOREST.md](./LAKE_FOREST.md)）；**6 己方 + 6 狼骑**（见 [UNITS.md](./UNITS.md)）。
- 玩家回合可**点选单位查看**；移动须拖**移动卡**后再点绿格；可普攻、结束行动（对手 AI 段见 [COMBAT.md](./COMBAT.md)）。点到不可通行格（城墙/树林）有提示。
- 默认逻辑分辨率 **竖屏 393×852**（iPhone 14 Pro）；棋盘 **拖动 + 滚轮/双指缩放**。缩放下限取 `BoardConfig.camera_zoom_min` 与「当前视口看全盘」的更小值；平移按 Camera2D 像素→世界 1:1（`camera_pan_sensitivity` 默认 1.0）。**竖向**往下滑动视角往下；左右仍为抓住地图跟手。

## 地块

- 类型表 `resources/terrain/terrain_catalog.tres`：**空草地**（可通行）、**直城墙**（不可通行）、**湖泊**（可通行）、**树林**（不可通行且挡攻击）。细则见 [LAKE_FOREST.md](./LAKE_FOREST.md)。
- 对战开局：`ClusterTerrainGenerator` 按内部 seed 成簇生成（不读预置 JSON；`terrain_map_path` 已废弃）。
- **移动与寻路**：8 邻接最短路，每步 1 移力；不可通行格不能进入或穿过；**禁止斜穿墙角**；路径中间的单位不挡路。
- 攻击距离按切比雪夫；**城墙不挡射击**；**树林挡中间格视线**（邻格不挡）。

## 表现

- **坐标**：逻辑格 `(x, y)` 先映射到地面 **XZ**（原点在盘心，顶面高度 `tile_height`），再经 **`camera_pitch_deg` + `camera_yaw_deg`（默认各 45°）** 正交投影到 SubViewport 2D。点选：相机逆变换后对格块 **Grass 菱形做点在多边形内**（2D 命中，等价射线落到可见格面）。`_gui_input` 的坐标已是棋盘局部坐标，不再二次局部化；触摸模拟出的鼠标事件被忽略，一次点按只触发一次点格。
- **视角**：仍用 **Camera2D** 平移/缩放视口；投影公式与旧 3D 斜视正交一致，棋盘呈斜 45° 俯视（非顶视）。默认缩放按视口**短边**适配 `camera_ortho_size`。`SubViewportContainer.stretch=true` 铺满棋盘区；Control 层另有同色 chrome，避免未同步时透出沙盘底色。
- **地块绘制**（`Polygon2D`，投影四边形）：
  - 草地：方 footprint `cell_size × tile_inset`（默认 **0.98U**）；顶面色按 `(x+y)%2` **`#B4A158` / `#8F884C`**。
  - 直城墙：草地底同上；格内居中条形墙身（厚 **0.16U**、长 **inset**），石砖 **`#9C958C` / `#716C65`**；按相邻同类 **0° / 90°** 转向（与旧 3D 规则一致）。
- **3D 网格资源**：`resources/terrain/meshes/*.tres` 仍供 headless 尺寸/生成脚本使用，**运行时沙盘不再实例化 MeshInstance3D**。
- **湖泊**：偏蓝顶面；**树林**：深绿顶面 + 树冠标记。
- **阴影**：**无 3D 方向光实时投影**。`BoardLook.shadow_*` 仍定义产品意图；2D 路径下单位使用 **脚下径向渐变软影**（`Sprite2D`），不随 Web 开关 3D 灯。若需强对比，可调 `unit_blob_opacity`。
- **BoardLook**：`background_color`（纯色 `#121820`，与沙盘 HUD 底同色）铺满棋盘区背板；`unit_modulate` 乘在角色 Sprite 上。已移除全屏后处理。
- **单位**：节点原点在**地面格心投影**（菱形几何中心，不是下顶点）。缩放按贴图**不透明内容高度**对齐 `unit_world_height`（避免顶部留白把角色缩小），再乘 `TacticalUnitDef.visual_scale`；`Sprite2D.offset` 对齐内容底边，**脚点留在格心**，躯干与头在脚点上方；HP 在头顶。脚下软影贴在脚点。`z_as_relative = false`，`z_index` 从 `1000` 起（高于全部格子），单位之间再按屏幕 Y 排序。
- **选中高亮**：格上半透明 `Polygon2D`——选中（蓝）、移动（绿）、攻击距离（红）。
- **不做**：WFC、迷雾、六边格。

## 验收（开发）

- Headless：`scripts/map/grid_board_test_runner.gd` → `GRID_BOARD_OK`（格坐标、2D 平移、棋盘色、墙条尺寸与转向、overlay、BoardLook 背景与脚下软影）。
- `scripts/units/terrain_movement_test_runner.gd` → `TERRAIN_MOVEMENT_OK`。
- `scripts/ui/sandbox_tap_test_runner.gd` → `SANDBOX_TAP_OK`（393×852 沙盘经 GUI 注入触摸/鼠标点格）。
- 完全：`bash tools/run_verify_runners.sh`。