# 地图编辑器 v1

> **已实现**（独立场景，默认 8×8）。对战沙盘仍使用 `resources/map/board_config.tres`（10×8）。

## 玩家能做什么

- 主菜单 **地图编辑** 进入独立编辑器（与沙盘对战分离）。
- 默认 **8×8** 盘（`resources/map/map_editor_board_config.tres`）。
- **点击格子** 在 **可走 / 不可走** 两态间切换；底栏显示当前格状态。
- **保存** / **加载** `user://maps/` 下的 JSON（文件名可改，默认 `map_001.json`）。

## JSON 格式（`tactical_map_v1`）

| 字段 | 说明 |
|------|------|
| `format` | 固定 `"tactical_map_v1"` |
| `width` / `height` | 整数格数 |
| `cells` | 长度 `width×height`，行优先（先 `y` 再 `x`），值为 `0` 可走、`1` 不可走 |

示例（2×2）：

```json
{
	"format": "tactical_map_v1",
	"width": 2,
	"height": 2,
	"cells": [0, 1, 1, 0]
}
```

## 验收（开发）

- Headless：`scripts/map/map_editor_test_runner.gd` 打印 `MAP_EDITOR_OK`。
- 轻量：`bash tools/run_light_verify.sh`（含 `map_editor.tscn` 加载烟测）。

## 未做（下一刀）

- 沙盘对战从 JSON 自定义地图开局。
- 地形影响移动/战斗规则。
