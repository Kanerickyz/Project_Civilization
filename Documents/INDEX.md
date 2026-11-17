# 战术战棋 — 文档索引

> 小地图战术战棋 · Godot 4.6 · 2D 斜 45° 棋盘 + Sprite2D 单位

玩法方向以 [GAME_VISION.md](./GAME_VISION.md) 为准。已经写进代码的规则以 Features 为准，并与代码对照。

## 快速导航

| 文档 | 说明 |
|------|------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | 当前工程状态、目录、系统划分 |
| [DEVELOPMENT_WORKFLOW.md](./DEVELOPMENT_WORKFLOW.md) | Agent 职责、纵切片、L0–L5、轻量/完全验收 |
| [GAME_VISION.md](./GAME_VISION.md) | 这是什么游戏、边界、当前做到哪 |
| [Features/TURN_CLOCK.md](./Features/TURN_CLOCK.md) | **回合钟**（已实现） |
| [Features/GRID_BOARD.md](./Features/GRID_BOARD.md) | **方格棋盘** · **2D 斜 45°** · Sprite2D 单位 |
| [Features/MAP_EDITOR.md](./Features/MAP_EDITOR.md) | **地图编辑器 v1** · 8×8 · 草地/直城墙 · JSON v2 存读 |
| [Features/UNITS.md](./Features/UNITS.md) | **战术单位** · 移动距离 / 对手移力池 · 触发被动 |
| [Features/COMBAT.md](./Features/COMBAT.md) | **普攻 / 胜负 / 对手 AI** |
| [Features/CARD_ACTIONS.md](./Features/CARD_ACTIONS.md) | **卡牌行动层** · 移/攻卡 · STS 抽弃 |

## 仓库里有什么

```
战术战棋/
├── Documents/
├── scenes/main/main_menu.tscn    # 主菜单
├── scenes/main/sandbox.tscn      # 对战沙盘
├── scenes/main/map_editor.tscn   # 地图编辑器
├── scripts/core/turn_clock.gd    # 回合钟
├── scripts/cards/                # 卡牌行动层
├── scripts/map/                  # 方格盘视图与配置
├── resources/map/board_config.tres
├── scripts/autoload/game_settings.gd
├── tools/install_godot.sh
├── tools/run_light_verify.sh
└── tools/run_verify_runners.sh
```

## 推荐 `res://` 结构

| 路径 | 职责 | 状态 |
|------|------|------|
| `scenes/main/main_menu.tscn` | 主菜单，进入沙盘或退出 | **已有** |
| `scenes/main/sandbox.tscn` | 沙盘：方格盘、回合 HUD、底栏手牌 | **已有** |
| `scripts/core/turn_clock.gd` | 玩家/对手交替，回合数 | **已有** |
| `scripts/cards/` | 行动卡、三库、抽弃 | **已有** |
| `scripts/autoload/game_settings.gd` | 音量与全屏设置存档 | **已有** |
| `scripts/ui/main_menu.gd` | 主菜单 | **已有** |
| `scripts/ui/sandbox.gd` | 沙盘界面（接入棋盘与手牌） | **已有** |
| `scripts/map/` | 方格盘 2D 视图、`BoardConfig` | **已有** |
| `resources/map/board_config.tres` | 盘尺寸、格距、镜头 | **已有** |
| `assets/fonts/` | 中文 UI 字体 | **已有** |
| `scripts/settlement/` | 定居点与产出 | 未做 |

## 引擎配置摘要

| 项 | 值 |
|----|-----|
| 引擎 | Godot **4.6**（安装脚本固定 4.6.3） |
| 项目名 | 战术战棋 |
| 版本 | 见 `project.godot` `application/config/version` |
| 特性标签 | `4.6`, `GL Compatibility` |
| 渲染器 | `gl_compatibility` |
| 窗口 | 393×852（iPhone 14 Pro 竖屏逻辑点），桌面覆盖 786×1704；`canvas_items` + `expand`；handheld 竖屏 |
| Web | `export_presets.cfg` 单线程 Web；GitHub Pages：`.github/workflows/deploy-pages.yml` |

## 当前里程碑（代码对齐）

| 模块 | 状态 | 说明 |
|------|------|------|
| 回合钟 | 当前 | 玩家/对手交替 |
| 方格盘 | 当前 | 2D 斜 45° 投影、Camera2D 拖拽缩放、Sprite2D 单位 |
| 单位移动 | 当前 | 玩家靠移动卡（无移力池）；对手用移力池 |
| 战斗 | 当前 | 普攻与胜负；玩家须打出攻击卡 |
| 卡牌行动 | 当前 | 玩家攻+移+主动技；友方可被普攻；STS 抽弃；底栏手牌 |
