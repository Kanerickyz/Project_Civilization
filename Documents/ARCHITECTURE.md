# 架构概览

Godot 4.6 · GL Compatibility · 横屏 UI（852×393 逻辑点）。

## 当前系统

- **入口**：`scenes/main/main_menu.tscn` → `sandbox.tscn`
- **回合**：`TurnClock`（`scripts/core/turn_clock.gd`），UI 只调用 `end_turn()`，不自写计数
- **地图**：方格 3D 盘、正交 ~45° 镜头、拖拽/滚轮（见 Features/GRID_BOARD）
- **设置**：`GameSettings` autoload 持久化音量/全屏（主菜单尚无设置 UI）

## 目录

| 路径 | 职责 |
|------|------|
| `scripts/core/` | 回合钟、加载烟测 |
| `scripts/ui/` | 主菜单、沙盘 HUD |
| `scripts/map/` | `BoardConfig`、`GridBoardView` |
| `resources/map/` | 棋盘 `.tres` |
| `scenes/main/` | 主菜单与沙盘场景 |
| `tools/` | Godot 安装与验收脚本 |

## 表现与逻辑

- 沙盘用 `Control` 全屏；棋盘在 `SubViewport` 内 3D 渲染，HUD 浮在上层。
- 单位占位为 `Sprite3D`（Billboard），逻辑坐标与格点后续由 gameplay 模块驱动。

## 扩展约定

新增系统时先写 Feature，再落代码。不要预搭未在愿景或 Feature 中立项的管理器。
