# project-autochess 美术镜像

自 [Kanerickyz/project-autochess](https://github.com/Kanerickyz/project-autochess) 复制的**美术资源**（`assets/` 整树），不含玩法脚本或场景。

## 目录

| 路径 | 内容 |
|------|------|
| `fonts/` | Noto Sans、DroidSansFallback（与根 `assets/fonts/` 的 UI 栈可并存，见下方说明） |
| `sprites/units/` | 动物/单位 emoji 风精灵（约 60+） |
| `sprites/paper_cutout/units/` | 蓝红剪纸风单位 |
| `sprites/paper_cutout/ui/` | 攻击/生命等 stat 图标 |
| `sprites/paper_cutout/env/` | 竞技场背景 |
| `sprites/` | 棋子 body/head 测试片等 |
| `audio/` | 占位（`.gdkeep`） |

战术沙盘当前使用 `sprites/units/wolf.png`（玩家）与 `pyre_guard.png`（对手）。

## 与根 `assets/` 重复说明

- **`assets/fonts/NotoSans-Regular.ttf`**：UI Theme（`resources/ui/ui_font.tres`）仍引用根目录副本；本目录内为 autochess 原路径保留。
- **`DroidSansFallback.ttf`**（本目录）≠ **`DroidSansFallbackFull.ttf`**（根目录中文 UI）；二者并存，未合并。

许可与字体说明见各子目录 `README.md`（若有）及 autochess 上游。
