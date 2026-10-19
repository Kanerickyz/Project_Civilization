# 方格棋盘 · 3D 斜俯视 · 2D 占位单位

> **已实现**（占位骨架 + 地块类型）。数值见 `resources/map/board_config.tres`。

## 玩家能做什么

- 主菜单进入**对战沙盘**：中央浮起方格盘。
- **拖拽**平移镜头、**滚轮**正交缩放。
- 棋盘为 **8×8**（默认）草地格；第 4 行（y=3）示例城墙带 `01101101`（草墙墙草墙墙草墙）；**4+4** 剪纸单位（见 [UNITS.md](./UNITS.md)）。
- 玩家回合可**点选己方单位**、按移动力移动、查看移动/攻击 overlay；可普攻、结束行动（对手 AI 段见 [COMBAT.md](./COMBAT.md)）。点城墙格提示「直城墙不可通行」。

## 地块

- 类型表 `resources/terrain/terrain_catalog.tres`：**空草地**（可通行）、**直城墙**（不可通行）。字段与 JSON 格式见 [MAP_EDITOR.md](./MAP_EDITOR.md)。
- 对战开局布局：`board_config.terrain_map_path`（默认 `res://resources/map/sandbox_battle_map.json`，tactical_map JSON）。路径为空、缺失、读不出或尺寸与 `grid_width × grid_height` 不符时，警告并回退全草地。
- **移动与寻路**：8 邻接最短路，每步 1 移力；不可通行格不能进入或穿过；**禁止斜穿墙角**（斜走一步时两侧正交邻格都须可通行）；路径中间的单位不挡路。单步上限 `move_range` 与移力扣除都按路径步数算；无城墙时与切比雪夫距离相同。
- 攻击距离仍按切比雪夫，城墙不挡射击。

## 表现

- **坐标**：整数方格 `(x, y)`，原点在盘心。
- **视角**：正交相机，相对水平面约 **45°** 仰角 + **45°** 偏航。
- **地块模型**：低多边形 + toon 渲染。尺寸按 `cell_size`（1U）与 `tile_height` 换算：
  - 草地底板 `cell_size × tile_inset`（默认 **0.98U**，仅留近原画级细缝；背景色在缝内露出）见方、厚 `tile_height`；**草地顶面**（含城墙格 surface 0）按 `(x+y)%2` 无光照平面色 `#B4A158` / `#8F884C`（`StandardMaterial3D` UNSHADED：格色不被主光洗黄，仍接收实时投影）；侧缘与草簇仍来自低模 mesh。
  - 直城墙在草地底板上，居中、沿格子中线贯穿 1U，高 0.6U（墙身 0.46U + 3 个城齿），厚 0.16U；**墙身石面**无光照纯色（`TerrainTypeDef.editor_color`）、仍投射实时阴影；顶面草地与棋盘格一致。
  - 生成脚本 `tools/terrain/generate_terrain_meshes.gd`（headless 运行，输出 `resources/terrain/meshes/*.tres`）；shader `resources/terrain/shaders/`（三级明暗、投影压到暗档并偏冷 + 反壳描边，兼容 GL Compatibility / Web）；材质 `resources/terrain/materials/`。
- **光照**：`BoardConfig.look` → `resources/map/board_look.tres`（`BoardLook`）。暖色主光（左上方斜照，影子落向右下）+ 冷色天光环境光 + 正交柔和投影；`WorldEnvironment` 仅设背景色与天光，不做全屏对比 / 饱和 / 曝光调色。
  - Web 与桌面默认均开实时投影（`shadow_on_web=true`；Compatibility 下带影灯多一遍绘制，可关以省帧时）。
- **单位脚下软影**：每个单位一片径向渐变平面，贴草面跟随 Sprite（不作 Sprite 子节点，否则被 billboard 卡片吞掉）；Sprite 不投实时影，乘 `unit_modulate` 暖色与场景同调。
- **单位表现**：Billboard `Sprite3D`；`unit_world_height`（默认 **0.88**）按纹理换算 `pixel_size`；正交 `camera_ortho_size` 约 **5.4**。
- **选中高亮**：格面上方半透明平面——选中（蓝）、移动（绿）、攻击距离（红）。
- **不做**：WFC、迷雾、六边格。

## 验收（开发）

- Headless：`scripts/map/grid_board_test_runner.gd` 打印 `GRID_BOARD_OK`（含地块网格、城墙尺寸与转向、overlay、光照 / 调色来自 BoardLook、脚下软影跟随与释放）；`scripts/units/terrain_movement_test_runner.gd` 打印 `TERRAIN_MOVEMENT_OK`（城墙阻挡、绕路、禁斜穿墙角、沙盘布局）。
- 完全：`bash tools/run_verify_runners.sh`。
