# 战术战棋：项目级工作规则

## 开始工作
- 用中文沟通；先读 [Documents/INDEX.md](Documents/INDEX.md)、相关设计文档和目标模块；检查 `git status`，保留用户修改。
- 设计意图来自 [Documents/GAME_VISION.md](Documents/GAME_VISION.md) 与 `Documents/Features/`。现有行为来自代码、场景与资源。发现冲突要说明，不把建议写成已完成。
- 写文档时遵守 [Documents/DEVELOPMENT_WORKFLOW.md](Documents/DEVELOPMENT_WORKFLOW.md)「养成规范」：**当前不做的默认不写进规格**。
- Godot 4.6、GDScript。默认入口 `scenes/main/main_menu.tscn`。沙盘占位是 `scenes/main/sandbox.tscn`。
- Cloud Agent 环境应提供 PATH 上的 `godot`（4.6.3）；可用 `GODOT_BIN` 覆盖。安装：`bash tools/install_godot.sh`。Headless 验证：`bash tools/run_light_verify.sh`，完全验收再跑 `bash tools/run_verify_runners.sh`。GUI 验收用桌面 DISPLAY（常见为 `:1`）；无声卡时引擎会回退 dummy 音频驱动，属预期。
- 用户当前请求优先于项目默认规则；只解决当前范围，不顺带重写游戏系统。
- **提出需求时先问验收方式**（见 [Documents/DEVELOPMENT_WORKFLOW.md](Documents/DEVELOPMENT_WORKFLOW.md)「验收方式」）：**轻量** = `bash tools/run_light_verify.sh` 加载通过即可，效果由用户验；**完全** = 现行 runner + 按 L 级 QA/GUI。未指定先问再做。

## 游戏约束
- 这是**回合制、格子上的战术战棋**（非 4X、非自走棋）：小地图、短局。不要引入商店养队、准备入座观战、胜后招募、三合一或战斗事件总线，除非先改愿景。
- 已落地的规则只有回合钟：开局第 1 回合、玩家行动；结束行动后轮到对手；对手也结束后，回合数 +1，回到玩家。见 [Documents/Features/TURN_CLOCK.md](Documents/Features/TURN_CLOCK.md)。
- 主菜单和沙盘上的格子、双方标记是**占位**。单位还不能移动，没有城市、科技、外交或胜负结算。
- 第一刀同时只做玩家对一个对手。宗教、文化胜利、世界议会和长科技树不进入当前切片。
- 以后的数值放 `resources/` 下的 `.tres`，避免在脚本里堆正式点数。当前没有数值资源。
- 表现与逻辑分离。界面默认按 iPhone 14 Pro 横屏逻辑点 852×393（约 19.5:9），横屏，GL Compatibility。中文用 `assets/fonts/DroidSansFallbackFull.ttf`。

## 实现与验证
- 规范见 [CONTRIBUTING.md](CONTRIBUTING.md)。保留 `.uid` 和导入侧车，不提交 `.godot/`、`.artifacts/`、导出凭据、日志与缓存。
- 不编辑生成缓存、不批量重写场景/资源；修改共享 Resource 前判断是否需 `duplicate()`。
- **轻量验收**：`bash tools/run_light_verify.sh`；不跑全套 runner、不代做 GUI/效果验收。
- **完全验收**：按改动跑现有 `scripts/**/*_test_runner.gd`（或 `bash tools/run_verify_runners.sh`）。不删断言或屏蔽错误来使检查变绿。UI 须 GUI 证据；Headless 通过不代表视觉通过。
- 交付说明验收方式、原因、验证结果与未覆盖项；日志、退出码和证据必须一致。

## Sub-agent 流程
- 主代理负责需求、任务拆分、共享文件、集成和交付；小型串行修改由主代理完成。跨模块切片按 [Documents/DEVELOPMENT_WORKFLOW.md](Documents/DEVELOPMENT_WORKFLOW.md) 派专职角色；设计已定要落地用 `implement` skill，完整纵切片用 `vertical-slice` skill。
- Cursor 角色在 `.cursor/agents/*.md`，用 Task 委派。Customize 里看不见就不算已加载；改为手读对应 `.md` 再传合同。不能声称文件已自动加载。
- 每个纵切片自带目标等级 L0–L5。同时最多三个子代理。未触达的职业不强制到场。`project.godot`、共享场景与枚举由主代理统一修改。
- **完全验收**下：集成后 QA 按目标等级给出结论，reviewer 只读审查；阻断退回实现。L5 只修缺陷。验证用 `verify-godot`，画面用 `gui-acceptance`。**轻量验收**不派 QA/GUI，加载烟测即可。
- 切片等级不取代文档里的里程碑。里程碑描述已实现范围，L0–L5 描述当前切片质量。

## Git
- `main` 保持可验证；新工作使用 `feat/`、`fix/`、`docs/` 或 `chore/` 分支，按功能拆提交。Cloud Agent 分支名另服从当次任务给出的前缀。
- **玩家可见改动合入时须 bump** `project.godot` 的 `application/config/version`（主菜单下方显示 `v…`）；纯文档/工具链除外。细则见 [CONTRIBUTING.md](CONTRIBUTING.md)「应用版本号」。
- 不改全局身份、不强推、不重置用户修改。发布、可见性改变和版本打标按用户任务授权执行。
