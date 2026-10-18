---
name: verify-godot
description: Runs Godot light smoke or full SceneTree test runners and reports exit codes plus SCRIPT ERROR. Use when implementing gameplay, changing resources, or claiming L2+ done under full acceptance.
---

# verify-godot

跑项目验证时用这个技能。先确认合同**验收方式**（轻量 / 完全）。不要另起空入口假装通过。

引擎：`godot`（4.6.3），可用 `GODOT_BIN` 覆盖。缺失时先 `bash tools/install_godot.sh`。

## 入口

### 轻量验收

```bash
bash tools/run_light_verify.sh
```

仅 import + 关键场景加载烟测。通过即可交付实现；效果由用户验收。不要用本技能冒充完全验收。

### 完全验收

```bash
bash tools/run_verify_runners.sh
```

该脚本会发现 `scripts/**/*_test_runner.gd` 并逐个运行。改了哪条规则，就确认对应 runner 在其中且失败时退出码非 0。

## 判定

- 退出码必须为 0。
- 日志可写 `.artifacts/validation/`，不提交。
- 扫描 `SCRIPT ERROR`、`Parse Error`、`ERROR:`。
- 不删断言、不屏蔽错误、不与编辑器资源导入并行。
- 只报告实跑命令、退出码和未覆盖项。Headless 通过不等于 GUI 通过。
