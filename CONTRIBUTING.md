# 开发与代码规范

## Git

从 `main` 创建 `feat/<topic>`、`fix/<topic>`、`docs/<topic>` 或 `chore/<topic>`；提交用 `feat(turn): ...`、`fix(map): ...` 等格式，一个提交解决一个问题。PR 说明行为、验证与必要画面证据。Cloud Agent 若被要求使用 `cursor/` 分支前缀，以该次任务为准。

项目使用 UTF-8。保留 `.uid` 和资产 `.import` 侧车，不提交 `.godot/`、`.artifacts/`、凭据或导出包。大文件接近 GitHub 单文件限制前评估 LFS，不只提交指针而遗漏对象。

### 应用版本号（主菜单可见）

主菜单下方显示的版本来自 `project.godot` 的 `application/config/version`（文案形如 `v0.1.0`）。

- **有玩家可见功能或行为合入**（玩法、UI、内容资源、影响试玩的修复）时：在**同一 PR** 内 bump 该字段，使合并进 `main` 后主菜单版本立刻可辨认。
- **纯文档 / 纯工具链 / 不影响玩家画面与规则的改动**：不必 bump。
- 建议语义：小修复 → patch（`0.1.0` → `0.1.1`）；可见功能 → minor（`0.1.0` → `0.2.0`）。不必为每次 bump 单独开 PR。
- Cloud Agent / 主代理交付玩家可见切片时：集成提交须包含版本 bump；未 bump 视为交付不完整。初始化版本 `0.1.0` 即本规则的起点。

## GDScript

- 遵循现有代码：tab 缩进；文件/函数/变量 `snake_case`，`class_name` PascalCase，常量/枚举 `UPPER_SNAKE_CASE`，私有成员前缀 `_`。
- 公开接口、资源字段和集合尽量声明类型；`:=` 仅用于明确类型，动态 `Dictionary.get()` 显式转换。
- 按类声明、常量、导出变量、状态、生命周期、公开接口、私有实现组织；顶层函数之间空一行。
- 用信号和明确接口连接模块；避免把地图、回合、城市和界面堆进同一个脚本。
- 资源使用 `res://`，玩家数据使用 `user://`，不写死个人路径。
- 缓存稳定引用，避免每帧扫描全树、加载资源或创建材质；清理信号和临时节点，遵守 `queue_free()` 生命周期。
- 边界处校验输入/资源；错误包含上下文，不能用静默回退隐藏逻辑错误。
- 随机数通过传入或可复现的 `RandomNumberGenerator` 控制，复现记录种子。

## Godot 资源与编辑器

- 正式数值进 `resources/` 下的 `.tres`（地图、单位、定居点等，目录随切片增加），保留加载接口兼容。当前初始化没有数值资源。
- 修改枚举须检查序列化整数及 `.tres`，不重排现有成员。
- 场景尽量用编辑器修改；文本修改保持资源 ID/UID 与引用。提交前确认没有丢失 `.uid` 或 `.import`。
- 共享 `Resource` 进入运行时实例前判断是否需 `duplicate()`。
- 视觉效果保持 **GL Compatibility**。2D 与界面放 `assets/`。中文界面使用 `assets/fonts/DroidSansFallbackFull.ttf`，不要改回不含中文的默认字体。
- 窗口默认 1280×720 横屏。色盲不只靠红绿区分阵营：同时使用文字或形状。

## Cursor

- 项目规则以根目录 [AGENTS.md](AGENTS.md) 为准。`.cursor/rules/` 只做入口，不复制长表。
- 跨模块功能按 [Documents/DEVELOPMENT_WORKFLOW.md](Documents/DEVELOPMENT_WORKFLOW.md) 派发；小型串行修改由主代理完成。
- Customize 里看不见的角色文件不算已加载；手读 `.cursor/agents/<role>.md` 再传合同。
- 可重复步骤用 `.cursor/skills/`：`design-brainstorm`、`implement`、`vertical-slice`、`verify-godot`、`gui-acceptance`。
- 开需求先确认验收方式（轻量 / 完全），见 [Documents/DEVELOPMENT_WORKFLOW.md](Documents/DEVELOPMENT_WORKFLOW.md)。
- 不把 Plan 草稿、提案文档或未跑过的测试写成已完成。

## 完成条件

按合同中的**验收方式**：

- **轻量**：`bash tools/run_light_verify.sh` 通过（关键场景可加载、无 SCRIPT/Parse Error）；效果与画面由用户自验；交付注明未代验项。
- **完全**：验收可复现，受影响的 test runner 通过，无新增解析错误，UI 有 GUI 验收，文档符合实装，独立审查无未处理阻断问题。

数值修改要说明它对回合长度、地图压力和双方强弱的影响。
