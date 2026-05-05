---
title: 安装与卸载
parent: ../README.md
---

# 安装与卸载

本文件是 Harness Engineering 规范的安装手册，记录一键集成脚本、占位符策略、Vendor / NoVendor 两种部署模式以及卸载流程的完整选项。

仓库根 `install.ps1` / `install.sh` 把规范文档 vendor 进你的项目，并为指定的 AI 编码工具渲染配置。

## 1. 一键集成

```powershell
# Windows / 跨平台（PowerShell 7+）
git clone https://github.com/shuaihuadu/harness-engineering.git
cd harness-engineering
./install.ps1 -TargetRepo D:\Path\To\YourRepo
```

```bash
# Linux / macOS（依赖 jq）
git clone https://github.com/shuaihuadu/harness-engineering.git
cd harness-engineering
./install.sh --target-repo /path/to/your/repo
```

默认会做四件事：

1. **Vendor 规范文档**：把 `agents/` `docs/` `templates/` `README.md` 同步进 `<your-repo>/.harness-engineering/`（与安装清单同住，一个隐藏目录装下所有 harness 产物）
2. **渲染 Copilot 配置**：`.github/copilot-instructions.md` + `.github/instructions/*`，链接指向上一步的 vendor 目录
3. **Custom Agent 默认全装**：交互模式下脚本会列出可选的 Custom Agent 模板，让你按编号 / stem / `all` / `none` 现场挑选，回车采纳默认（当前 Copilot target 默认 `all`，全装）；非交互模式（`-NonInteractive` / `-Force`）走 `target.json` 的 `default_select`，也可以始终用 `-CopilotAgents` / `--copilot-agents` 显式覆盖
4. **写入安装清单**：`<your-repo>/.harness-engineering/manifest.json` 记录本次写入的所有文件（含 sha256）+ 本次填入的占位符（`replacements`），供 `uninstall` 使用，并在下次重装时自动预填

## 2. 占位符填入策略

需要 3 个占位符（`TEST_COMMAND` / `LINT_COMMAND` / `HARNESS_REPO_REF`），优先级：

```
CLI 参数  >  上次 manifest.replacements  >  自动探测  >  交互输入 / 空（→ <未配置>）
```

- **自动探测**：脚本会读取 `*.csproj` / `package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` / `global.json` 等推断主语言，进而映射出测试和 Lint 命令的合理默认值
- **菜单挑选 + 自定义**：`TEST_COMMAND` / `LINT_COMMAND` 在交互模式下不再裸奔为输入框，而是列出主流命令（`dotnet test` / `npm test` / `pytest` / `cargo test` / `go test ./...` / `mvn test` 等），同时支持 `c` 自定义、`s` 跳过；探测到的值会被插到首位并标注「推荐 / detected」，回车即采纳
- **重装零输入**：上次安装的 `replacements` 写在 manifest 里，再次运行 `install` 时会自动作为最高优先级默认，覆盖探测结果
- **`<未配置>` 占位**：`TEST_COMMAND` / `LINT_COMMAND` 选「跳过」时会被填为字面量 `<未配置>`，便于后续用 `grep '<未配置>'` 一次性补充
- **零交互**：`-NonInteractive` 跳过所有 prompt（探测出什么用什么，仍缺则填 `<未配置>`）；`-Force` 隐含 `-NonInteractive` 并自动覆盖一切冲突

## 3. 卸载

```powershell
./uninstall.ps1 -TargetRepo D:\Path\To\YourRepo            # 安全卸载（用户改过的文件默认保留）
./uninstall.ps1 -TargetRepo D:\Path\To\YourRepo -Force     # 一并清理用户改过的文件
./uninstall.ps1 -TargetRepo D:\Path\To\YourRepo -DryRun    # 只预览
```

更多用法（多 target、占位符、`-Force` / `-DryRun` / `-NoVendor` 等）见 [`../agents/_integrations/README.md`](../agents/_integrations/README.md)。

## 4. Vendor 模式

默认行为是把 `agents/`、`docs/`、`templates/`、`README.md` **整份复制**到你的仓库 `.harness-engineering/` 下，这意味着：

- ✅ 离线可用、链接在采用方仓库内可点
- ✅ 规范副本与采用方仓库同步进入版本控制，可 diff、可回滚
- ✅ 与 `manifest.json` 同住一个隐藏目录，不污染 `docs/` 树；整块卸载干净
- ⚠️ 采用方仓库会多 ~300KB Markdown
- ⚠️ 规范升级 = 每个采用方仓库重跑一次 `install`（manifest 会自动 diff，已存在且未改的文件会 skip）

> 想换个目录名？交互模式下 vendor 路径会有 prompt（回车用默认 `.harness-engineering`）；非交互可显式传 `-VendorHarnessTo <path>` / `--vendor-harness-to <path>`。

## 5. NoVendor 模式

如果你希望不在采用方仓库落 vendor 副本（例如让链接指向 GitHub 远端），使用：

```powershell
./install.ps1 -TargetRepo X -NoVendor -HarnessRepoRef https://github.com/shuaihuadu/harness-engineering/blob/main
```

`-NoVendor` 模式下 `{{HARNESS_REPO_REF}}` 会被替换成你提供的 URL；缺点是 Custom Agent 里的链接需要联网才能跳转。两种模式适合不同场景，按需选择。
