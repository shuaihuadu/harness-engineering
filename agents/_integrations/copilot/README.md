# GitHub Copilot 集成模板

本目录是 [Harness Engineering](../../README.md) 给 **GitHub Copilot**（VS Code / GitHub.com / Copilot CLI）准备的"开箱即用安装包"源。

> **重要**：本目录下的所有文件都**不是**本仓库自身在用的 Copilot 配置——它们是被 [`install.ps1`](../../../install.ps1) / [`install.sh`](../../../install.sh) 渲染并落到**采用方仓库**的样板源。Copilot 只识别仓库根 `.github/`，不会自动加载本目录。
>
> **后缀约定**：
> - `*.template.md`：含占位符（`{{KEY}}`）或正文拼装指令（`{{INCLUDE_BODY:}}` / `{{INCLUDE:}}`），装时由 sync-engine 渲染。
> - `*.md`（不带 `.template`）：verbatim 源，照原样字节拷贝。
> - `*.skeleton.md`：人手抄写的骨架（集中收纳在 [`../_skeletons/`](../../_skeletons/)，如 `copilot-custom-agent.skeleton.md`），用 `<占位>` 而非 `{{KEY}}`，不进 sync-engine、不落到采用方仓库。

## 1. 渲染规则（target.json）

整个目录的渲染流程由 [`target.json`](./target.json) 声明。安装到采用方仓库后的最终落点：

| 源文件 / 源目录                                   | 落点                                     | 装到哪、给谁用                                     |
| ------------------------------------------------- | ---------------------------------------- | -------------------------------------------------- |
| `copilot-instructions.template.md`                | `.github/copilot-instructions.md`        | Copilot 全会话自动加载                             |
| `instructions/*.instructions.template.md`         | `.github/instructions/*.instructions.md` | 按 `applyTo` 自动加载                              |
| `custom-agents/*.agent.template.md` (× 12)        | `.github/agents/*.agent.md`              | Chat 输入框下方的 Agent 下拉手动切换               |
| `prompts/*.prompt.md` (× 4)                       | `.github/prompts/*.prompt.md`            | `/<name>` 显式触发                                 |
| `../../_skills/*/SKILL.md`                        | `.github/skills/*/SKILL.md`              | 模型按 description 语义命中后自动调用              |
| `../../templates/*.md` (× 4)                      | `.github/templates/*.md`                 | 给 Skills / Prompts / 人手共用的产物模板           |
| `handbook.md`                                     | `{{VENDOR_DIR}}/HANDBOOK.md`             | 操作手册，10 分钟上手                              |
| `vendor-readme.template.md`                       | `{{VENDOR_DIR}}/README.md`               | 解释 vendor 目录角色 + gitignore 建议                  |
| `../../docs/{concepts,ai-usage,repo-layout,tech-debt-gc}.md` + `../../docs/stages/*.md` | `{{VENDOR_DIR}}/docs/*.md` | 设计文档（深度阅读）                               |

安装产物分两个目录：

- **`.github/`**：Copilot 真正读的所有文件，开箱即用
- **`{{VENDOR_DIR}}/`**（默认 `.he/`，可用 `--vendor-harness-to <path>` 改）：HANDBOOK + 设计文档 + 安装清单 (`manifest.json`) + 安装日志 (`install.log`) + 卸载脚本 (`uninstall.ps1`)

## 2. 关键设计：自包含的 .github/

12 个 `.agent.template.md` 通过 [`{{INCLUDE_BODY: ...}}`](../../../scripts/lib/sync-engine.ps1) 指令把对应 `agents/<name>/AGENT.md` 与 `agents/<name>/prompt.md` 的正文 inline 进 `.github/agents/*.agent.md`。

**收益**：

- `.github/agents/*.agent.md` 自包含，不依赖 `{{VENDOR_DIR}}/agents/`（后者甚至不会被装到采用方）
- 用户把 `{{VENDOR_DIR}}/` 加进 `.gitignore` 也不影响 Copilot Agent 工作
- 模板源（`AGENT.md` / `prompt.md`）依然是单一事实来源；改了它，重跑 install 就同步

INCLUDE 指令在渲染时同步做"安全降级"：把内嵌指向 `../_shared/`、`../../docs/`、`../../README.md`、`AGENT.md` 的相对链接外壳剥成纯文本，避免 `.github/` 下出现 broken link。

## 3. 一键安装

仓库根脚本 [`install.ps1`](../../../install.ps1) / [`install.sh`](../../../install.sh) 是**幂等**的：源未变化时再次运行不写盘、不弹提示；源更新时按交互策略处理冲突 / 孤儿。

### 3.1 交互式（首次安装）

```powershell
./install.ps1 -TargetRepo D:\Path\To\YourRepo
```

```bash
./install.sh --target-repo /path/to/your/repo
```

### 3.2 参数式（CI 友好）

```powershell
./install.ps1 `
    -TargetRepo D:\Github\shuaihuadu\Inkwell `
    -ProjectName Inkwell `
    -ProjectOneLiner '基于 Microsoft Agent Framework 的 AI 内容平台' `
    -PrimaryLanguage 'C#' `
    -TechStack '.NET 10 + ASP.NET Core' `
    -TestCommand 'dotnet test' `
    -LintCommand 'dotnet format --verify-no-changes' `
    -Force -NoDelete
```

### 3.3 同步语义（幂等 + 冲突 + 孤儿）

| 场景                                 | 行为                                                        |
| ------------------------------------ | ----------------------------------------------------------- |
| 目标文件不存在                       | 写入                                                        |
| 目标文件存在且内容一致               | 静默跳过（`skip ... unchanged`）                            |
| 目标文件存在但内容不一致（**冲突**） | 交互提示 `[O]verwrite / [K]eep / [A]ll-overwrite / a[B]ort` |
| 源文件已删除但目标仍存在（**孤儿**） | 交互提示 `[D]elete / [K]eep / [A]ll-delete / a[B]ort`       |

### 3.4 关键选项

| 选项                                                | 说明                                                                                                                                                                                 |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-CopilotAgents <list>` / `--copilot-agents <list>` | 选择安装哪些 Custom Agent；**默认 `all`**（全装 12 个，覆盖 H1–H6 + 横切，并启用孤儿检测）；填具体 stem（如 `h3-detailed-design-reviewer,h5-coding-executor`）只装指定项；填 `none` 一个都不装 |
| `-Force` / `--force`                                | 全自动：所有冲突直接覆盖，所有孤儿直接删除；不弹任何提示                                                                                                                             |
| `-NoDelete` / `--no-delete`                         | 一律不删除孤儿（即便 `-Force` 也不删）；CI 升级推荐配合此选项                                                                                                                        |
| `-DryRun` / `--dry-run`                             | 只打印动作不写盘                                                                                                                                                                     |

### 3.5 升级流程

源仓库（harness-engineering）有更新后，到采用方仓库重新跑同样命令：

```powershell
# 推荐：先 DryRun 看看会变什么
./install.ps1 -TargetRepo <your-repo> ... -DryRun
# OK 再正式跑
./install.ps1 -TargetRepo <your-repo> ... -Force
```

完成后扫一下残留占位符：

```powershell
Select-String '\{\{' <your-repo>/.github -Recurse
```

## 4. 占位符

模板内全部用 `{{...}}` 双花括号占位。脚本会一次性替换；除下表外，正文里所有跨文件引用都通过 `{{INCLUDE_BODY: ...}}` inline，不再依赖 `{{HARNESS_REPO_REF}}` 之类的远程引用。

| 占位符                             | 含义                                                         | 示例                                |
| ---------------------------------- | ------------------------------------------------------------ | ----------------------------------- |
| `{{TEST_COMMAND}}`                 | 验收测试命令                                                 | `dotnet test`                       |
| `{{LINT_COMMAND}}`                 | 代码风格检查命令                                             | `dotnet format --verify-no-changes` |
| `{{HARNESS_REPO_REF}}`             | vendor 路径标识                                              | `.he`（默认）      |
| `{{HARNESS_REPO_REF_FROM_GITHUB}}` | 从 .github/ 回指 vendor 的相对路径（按文件深度自动算 `../`） | `../.he`           |

## 5. 不在范围内

- **硬质量门禁**：Copilot code review 是建议性评论，不是 status check。真正的拦截器是 GitHub Actions + Branch protection（采用方自管），不在本目录提供模板。
- **MCP server 配置**：与 Agent 包装无关，由采用方按需在 `.vscode/mcp.json` / `~/.config/copilot/mcp.json` 自管。
- **模型选择 / 计费 / 扩展安装**：采用方自处理。

## 6. 同步策略

当 [Harness Engineering 规范](../../README.md) 或具体 Agent 的 `AGENT.md` / `prompt.md` 更新时：

1. 优先改源（`agents/<name>/AGENT.md` / `prompt.md` / `templates/*.md` / `docs/*.md`），而不是模板
2. 模板（本目录下 `*.template.md`）只承担"工具特定的包装"职责，不重复源内容
3. 采用方升级时重新跑一次 `install.ps1` / `install.sh`（加 `-Force` 自动接受变更）即可
