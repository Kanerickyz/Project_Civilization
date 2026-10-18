# 文明战棋 — 文档索引

> 小规模、快节奏的文明式战棋 · Godot 4.6 · 初始化

玩法方向以 [GAME_VISION.md](./GAME_VISION.md) 为准。已经写进代码的规则以 Features 为准，并与代码对照。

## 快速导航

| 文档 | 说明 |
|------|------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | 当前工程状态、目录、系统划分 |
| [DEVELOPMENT_WORKFLOW.md](./DEVELOPMENT_WORKFLOW.md) | Agent 职责、纵切片、L0–L5、轻量/完全验收 |
| [GAME_VISION.md](./GAME_VISION.md) | 这是什么游戏、和文明的差别、当前做到哪 |
| [Features/TURN_CLOCK.md](./Features/TURN_CLOCK.md) | **回合钟**（已实现） |
| [Features/HEX_MAP.md](./Features/HEX_MAP.md) | **有限六边地图** · WFC · 战略迷雾 · **3D ~45° 俯视** |

## 仓库里有什么

```
文明战棋/
├── Documents/
├── scenes/main/main_menu.tscn    # 主菜单
├── scenes/main/sandbox.tscn      # 沙盘（六边地图）
├── scripts/core/turn_clock.gd    # 回合钟
├── scripts/map/                  # 六边 / WFC / 迷雾 / 视图
├── resources/map/map_config.tres
├── scripts/autoload/game_settings.gd
├── tools/install_godot.sh
├── tools/run_light_verify.sh
└── tools/run_verify_runners.sh
```

## 推荐 `res://` 结构

| 路径 | 职责 | 状态 |
|------|------|------|
| `scenes/main/main_menu.tscn` | 主菜单，进入沙盘或退出 | **已有** |
| `scenes/main/sandbox.tscn` | 沙盘：六边地图、迷雾、结束行动 | **已有** |
| `scripts/core/turn_clock.gd` | 玩家/对手交替，回合数 | **已有** |
| `scripts/autoload/game_settings.gd` | 音量与全屏设置存档 | **已有**（主菜单尚无设置界面） |
| `scripts/ui/main_menu.gd` | 主菜单 | **已有** |
| `scripts/ui/sandbox.gd` | 沙盘界面（接入地图） | **已有** |
| `scripts/map/` | 六边坐标、WFC、战略雾、3D 地图视图 | **已有**（无单位移动） |
| `resources/map/map_config.tres` | 地图半径/六边尺寸/WFC 重试等 | **已有** |
| `assets/fonts/` | 中文 UI 字体 | **已有** |
| `scenes/map/` | 独立地图场景 | 未做（逻辑在 scripts/map） |
| `scripts/settlement/` | 定居点与产出 | 未做 |
| `scripts/combat/` | 战棋战斗结算 | 未做 |

## 引擎配置摘要

| 项 | 值 |
|----|-----|
| 引擎 | Godot **4.6**（安装脚本固定 4.6.3） |
| 项目名 | 文明战棋 |
| 版本 | `0.4.0`（主菜单显示） |
| 特性标签 | `4.6`, `GL Compatibility` |
| 渲染器 | `gl_compatibility` |
| 窗口 | 852×393（iPhone 14 Pro 横屏逻辑点），桌面覆盖 1704×786；`canvas_items` + `expand`；handheld 横屏 |
| Web | `export_presets.cfg` 单线程 Web；GitHub Pages：`.github/workflows/deploy-pages.yml` |

## 里程碑

| 阶段 | 目标 | 状态 |
|------|------|------|
| 初始化 | Harness、主菜单、沙盘、回合钟 | 已完成 |
| 地图雾 | 有限六边、WFC、战略迷雾、3D ~45° 镜头 | 当前 |
| 下一刀 | 单位移动与短交锋 | 未开始 |

里程碑只描述仓库里有什么。单次改动做到哪一步，用 L0–L5，见 [DEVELOPMENT_WORKFLOW.md](./DEVELOPMENT_WORKFLOW.md)。

## 协作入口

项目规则在根目录 [AGENTS.md](../AGENTS.md)，代码规范在 [CONTRIBUTING.md](../CONTRIBUTING.md)。Cursor 角色、规则和技能在 `.cursor/`。

## 维护说明

- 新增场景或 Autoload 后，更新本页状态表。
- 重大设计变更同步愿景与 Features。当前不做的内容默认不写进规格。
- 不把别的项目（包括自走棋）的系统文档抄进本仓库。
