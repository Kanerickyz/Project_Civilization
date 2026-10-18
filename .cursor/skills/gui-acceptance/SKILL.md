---
name: gui-acceptance
description: Collects L4 presentable GUI evidence for the menu, sandbox map, and turn readout. Use for visual, camera, UI, or audio changes, or when claiming L4/L5.
---

# gui-acceptance

仅在合同为**完全验收**且目标含 L4/画面门禁时使用。**轻量验收**不跑本技能（效果由用户自验）。

Headless 通过不够。UI、图标、相机或音频改动必须留下 GUI 证据。

## 记录

版本、入口、操作、预期、实际结果、截图或录屏路径。产物放 `.artifacts/`，不提交。

默认入口：`scenes/main/main_menu.tscn`。按合同覆盖主菜单、沙盘和回合文案。

## L4 清单

- 1280×720 与较小窗口
- 主菜单、沙盘、当前回合与行动方可读
- 中文不是方框
- 阵营不只靠红绿区分（同时有「我 / 彼」或等价文字）
- 缩放与 HUD 不被遮挡
- 音频不盖过 UI；无音频则写明未覆盖
- 性能若声称改善，必须有 Profiler 采样

未运行的项标「未验证」，不能写成已通过。
