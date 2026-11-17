# project-autochess 美术镜像

自 [Kanerickyz/project-autochess](https://github.com/Kanerickyz/project-autochess) 复制的**美术资源**（上游 `assets/` 整树），不含玩法脚本或场景。本目录对应上游路径前缀 `assets/` → `assets/autochess/`；`.import` 的 `source_file` 已改写。

## 目录

| 路径 | 内容 |
|------|------|
| `branding/` | 应用图标 `game_icon.png`（`project.godot` `config/icon`） |
| `fonts/` | Noto Sans、DroidSansFallback（与根 `assets/fonts/` 的 UI 栈可并存） |
| `sprites/units/` | 动物/单位 emoji 风精灵 |
| `sprites/paper_cutout/units/` | 蓝红剪纸风单位 |
| `sprites/paper_cutout/ui/` | 攻击/生命等 stat 图标（信息卡已用） |
| `sprites/paper_cutout/env/` | 竞技场背景 |
| `sprites/paper_cutout/shop/` | 商店/招募贴图（镜像入库，未接线） |
| `sprites/combat/combo/` | 连击特效帧（镜像入库，未接线） |
| `sprites/placeholders/` | 开发占位角色 |
| `sprites/` | 棋子 body/head 测试片等 |
| `ui/main_menu/` | 主菜单背景/Logo/按钮贴图（背景与 Logo 已接线） |
| `ui/recruit/` | 招募 dissolve shader（镜像入库，未接线） |
| `audio/` | 占位（`.gdkeep`） |

## 沙盘单位贴图

`resources/units/*.tres` 使用 `sprites/paper_cutout/units/` 蓝/红稿（游侠/盾卫/大剑/狼骑兵/鼓手）。

## 与根 `assets/` 重复说明

- **`assets/fonts/NotoSans-Regular.ttf`**：UI Theme（`resources/ui/ui_font.tres`）仍引用根目录副本；本目录内为 autochess 原路径保留。
- **`DroidSansFallback.ttf`**（本目录）≠ **`DroidSansFallbackFull.ttf`**（根目录中文 UI）；二者并存，未合并。

许可与字体说明见各子目录 `README.md`（若有）及 autochess 上游。
