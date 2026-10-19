# 地图编辑器 v1

> **已实现**（独立场景，默认 8×8）。对战沙盘使用 `resources/map/board_config.tres`（10×8）及其 `terrain_map_path` 指向的布局（见 [GRID_BOARD.md](./GRID_BOARD.md)）。

## 玩家能做什么

- 主菜单 **地图编辑** 进入独立编辑器（与沙盘对战分离）。
- 默认 **8×8** 盘（`resources/map/map_editor_board_config.tres`），全盘初始为空草地。
- **点击格子** 按地块类型表顺序轮换：**空草地 → 直城墙 → 空草地**；底栏显示本格坐标与类型名。
- 直城墙按相邻城墙自动转向：仅南北有相邻城墙时沿南北摆放，否则沿东西。
- **保存** / **加载** `user://maps/` 下的 JSON（文件名可改，默认 `map_001.json`）。

## 地块类型

| id | 显示名 | 可通行 | v1 旧码 |
|----|--------|--------|---------|
| `grass` | 空草地 | 是 | `0` |
| `wall_straight` | 直城墙 | 否 | `1` |

- 类型表：`resources/terrain/terrain_catalog.tres`（顺序即点格轮换顺序；`default_id = grass`）。
- 单个类型：`resources/terrain/<id>.tres`（`TerrainTypeDef`：可通行性、旧码、网格、材质、是否按邻格转向）。

## JSON 格式（`tactical_map_v2`，保存时写入）

| 字段 | 说明 |
|------|------|
| `format` | 固定 `"tactical_map_v2"` |
| `width` / `height` | 整数格数 |
| `cells` | 长度 `width×height`，行优先（先 `y` 再 `x`），值为地块 id 字符串 |

```json
{
	"format": "tactical_map_v2",
	"width": 2,
	"height": 2,
	"cells": ["grass", "wall_straight", "wall_straight", "grass"]
}
```

### 兼容旧文件（`tactical_map_v1`）

- 仍可加载：`cells` 为整数，`0` → `grass`，其它非零（历史上的 `1` / `2`）→ `wall_straight`。再次保存即写成 v2。
- v2 中未知 id 或非字符串值：警告并按默认地块（空草地）处理；格式或尺寸错误则加载失败。

## 验收（开发）

- Headless：`scripts/map/map_editor_test_runner.gd` 打印 `MAP_EDITOR_OK`（v2 存读、v1 迁移、未知 id 回退、点格轮换）。
- 完全：`bash tools/run_verify_runners.sh`。
