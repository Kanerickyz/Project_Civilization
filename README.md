# 文明战棋

小规模、快节奏的文明式战棋。Godot 4.6。

设计与协作入口见 [Documents/INDEX.md](Documents/INDEX.md)。项目规则见 [AGENTS.md](AGENTS.md)。

## 本地运行

需要 PATH 上的 `godot`（4.6.3）。可执行：

```bash
bash tools/install_godot.sh
godot --path .
```

轻量加载检查：

```bash
bash tools/run_light_verify.sh
```

视口按 iPhone 14 Pro 横屏比例（逻辑点约 852×393）。Web 导出预设见 `export_presets.cfg`（单线程，便于 GitHub Pages）。

## GitHub Pages

`main` 推送或手动触发 `.github/workflows/deploy-pages.yml` 后发布 Web 构建。

预期地址（仓库 Pages 启用后）：

`https://kanerickyz.github.io/Project_Civilization/`

仓库需在 **Settings → Pages** 将 Source 设为 **GitHub Actions**（首次部署前）。
