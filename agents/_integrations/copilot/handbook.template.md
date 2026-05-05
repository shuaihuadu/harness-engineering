# Harness Engineering · 操作手册（HANDBOOK）

这份手册写给已经把 Harness Engineering v0.0.1 安装到自家仓库的人。**目标是你 10 分钟之内能用起来**：知道每个目录是干嘛的、什么时候切哪个 Agent / 用哪个 Prompt、怎么修模板、卸载升级怎么办。

> 你看到的这份 HANDBOOK 是**已渲染产物**——所有占位符已经被你安装时给的实际值替换掉了，可以直接读。

---

## 目录

1. [5 分钟速通：装完后该干啥](#1-5-分钟速通装完后该干啥)
2. [全流程一览：H1 → H6 + Hx](#2-全流程一览h1--h6--hx)
3. [`.github/` 里都装了什么](#3-github-里都装了什么)
4. [`.harness-engineering/` 里都装了什么](#4-harness-engineering-里都装了什么)
5. [Templates 怎么用、怎么改](#5-templates-怎么用怎么改)
6. [Skills / Prompts / Agents 速查](#6-skills--prompts--agents-速查)
7. [常见问题 / 排查 / 升级 / 卸载](#7-常见问题--排查--升级--卸载)

---

## 1. 5 分钟速通：装完后该干啥

1. **看一眼板**：仓库根没有 `task-board.md`？把 `.github/templates/task-board.md` 复制到根，去掉示例行。
2. **挑个最小任务起手**：在 Copilot Chat 里输入 `/new-task` + 你想做的小事；它会反问、起草 `docs/06-tasks/T-001-xxx.md`、登记 `task-board.md`。
3. **人工审任务说明**：看 `允许修改的文件` / `Verify 命令` 是否合理；OK 就把 `task-board.md` 里这行的 `status` 改 `ready`。
4. **切到 `H5-CodingExecutor`**：在 Copilot Chat 顶部 Agent 下拉里选它，让它按任务说明执行。
5. **提交前切到 `H5-CommitAuditor`**：让它机械化校验 commit message 六字段（Design / Tests / Verify / Docs / Risk / Task）。

走通这一圈，剩下的功能（H1 反问需求 → H2 ADR → H3 设计评审 → H4 测试用例 → H6 release notes → Hx 文档巡检）就是同一套手势的复制粘贴。

---

## 2. 全流程一览：H1 → H6 + Hx

```
┌─────────────────────── 一个特性 / 一次发版的生命周期 ───────────────────────┐
│                                                                              │
│  H1 需求          → H1-RequirementsInterviewer  → docs/01-requirements/      │
│  H1 影响图        → H1-RepoImpactMapper         → docs/01-requirements/      │
│  H2 架构 / ADR    → H2-ArchitectAdvisor         → docs/03-architecture/      │
│  H3 详细设计评审  → H3-DesignReviewer           → docs/04-detailed-design/   │
│  H4 测试用例      → H4-TestCaseAuthor           → docs/05-test-design/       │
│  H5 起任务        → /new-task                   → docs/06-tasks/             │
│  H5 编码          → H5-CodingExecutor           → 改源码 + Verify            │
│  H5 审提交        → H5-CommitAuditor            → 拒不合格的 commit          │
│  H6 发版说明      → H6-ReleaseNoteWriter        → docs/08-releases/          │
│  Hx 文档腐化巡检  → Hx-DocGardener              → 标 deprecated / 待清理     │
│                                                                              │
│  阶段切换前 → /run-gate 跑 phase-gate-checklist                              │
│  评审落档   → /log-review 把会议纪要归到 docs/07-reviews/                    │
│  对账       → /sync-board 把板和实际 commit 对一遍                           │
└──────────────────────────────────────────────────────────────────────────────┘
```

不强制按 H1 → H6 全走完才能动手；中小变更可以从 H5 起跳，但要回头补 `requirements.md` / `task-board.md` 链路。

---

## 3. `.github/` 里都装了什么

```
.github/
├── copilot-instructions.md          ← 仓库总指令；何时切哪个 Agent / 用哪个 Prompt
├── instructions/                    ← 文件类型相关的"规则集"，按 applyTo 自动加载
│   ├── coding-style.instructions.md
│   ├── commit-format.instructions.md
│   └── docs-style.instructions.md
├── agents/                          ← 9 个 Custom Agent，下拉菜单可选
│   ├── h1-repo-impact-mapper.agent.md
│   ├── h1-requirements-interviewer.agent.md
│   ├── h2-architect-advisor.agent.md
│   ├── h3-design-reviewer.agent.md
│   ├── h4-test-case-author.agent.md
│   ├── h5-coding-executor.agent.md
│   ├── h5-commit-auditor.agent.md
│   ├── h6-release-note-writer.agent.md
│   └── hx-doc-gardener.agent.md
├── skills/                          ← 4 个 Skill，Copilot 按 description 自动调
│   ├── ai-task-brief-writer/SKILL.md
│   ├── commit-message-formatter/SKILL.md
│   ├── phase-gate-runner/SKILL.md
│   └── traceability-linker/SKILL.md
├── prompts/                         ← 4 个 Slash Command
│   ├── new-task.prompt.md
│   ├── run-gate.prompt.md
│   ├── log-review.prompt.md
│   └── sync-board.prompt.md
└── templates/                       ← 4 个产物模板，AI 与人手共用
    ├── ai-task-brief.md
    ├── phase-gate-checklist.md
    ├── review-record.md
    └── task-board.md
```

**这 29 个文件都是 Copilot 开箱即用的——不需要你再做任何配置，进 Copilot Chat 直接选 Agent / 输 `/` 就有。**

---

## 4. `.harness-engineering/` 里都装了什么

```
.harness-engineering/
├── HANDBOOK.md       ← 你正在读的这份手册
├── README.md         ← 解释这个目录的角色 + .gitignore 建议
├── docs/             ← 设计文档（stages.md / repo-layout.md / tech-debt-gc.md）
├── manifest.json     ← 安装清单，uninstall 用
├── install.log       ← 每次 install/uninstall 追加一行
└── uninstall.ps1     ← 一键反向清理
```

这个目录的作用是**让你随时能查文档、能干净卸载**。安装完成后**它不需要再被修改**——你做的修改都应该发生在 `.github/` 里。

如果你觉得它跟项目本身无关、不想把它入版本库，**推荐在 `.gitignore` 里加上**：

```gitignore
.harness-engineering/
```

代价：团队其他人 `git pull` 之后没有 HANDBOOK 和 docs/，得自己再跑一次 `install.ps1`。如果想让所有人都能直接读这份手册，就**别 ignore**。

---

## 5. Templates 怎么用、怎么改

`.github/templates/` 里 4 个文件是**产物的初始骨架**，分两种用法：

### 5.1 直接复制使用

需要在仓库里建一个新文档（比如要起任务板）：

```powershell
# 例：从模板初始化任务板
Copy-Item .github/templates/task-board.md task-board.md
```

然后按里面的注释自己填。

### 5.2 让 Agent / Prompt 引用

`/new-task` 会读 `.github/templates/ai-task-brief.md`、`/run-gate` 会读 `.github/templates/phase-gate-checklist.md`、`/log-review` 会读 `.github/templates/review-record.md`、`/new-task` 也会同步登记 `task-board.md`。

**所以，你修改 `.github/templates/*.md` 之后：**

- 直接复制使用的人下一次复制就拿到新版
- AI 在执行 Prompt 时会读到新版
- **不需要重启 VS Code，不需要重跑 install.ps1**

### 5.3 推荐的修改方向

| 模板                      | 你应当根据自家情况调整的字段                              |
| ------------------------- | --------------------------------------------------------- |
| `ai-task-brief.md`        | `Verify 命令` 一行：换成你仓库真实的构建/测试命令         |
| `phase-gate-checklist.md` | 各 H 阶段的清单：删掉与你团队无关的项，加上你团队额外要求 |
| `review-record.md`        | `参与者角色`、`脱敏要求`：按公司合规要求改                |
| `task-board.md`           | 列字段：增减你想要的列（如 `priority`、`epic`）           |

### 5.4 不推荐的修改方向

- ❌ 删除 frontmatter 字段——Skills / Prompts 在解析时依赖它们
- ❌ 在 `phase-gate-checklist.md` 里写"AI 必须自动通过"——那 gate 就废了
- ❌ 把模板改成具体某个任务的内容——模板要保持通用

---

## 6. Skills / Prompts / Agents 速查

### Skills（按 description 自动触发）

| Skill                      | 何时被触发                                  |
| -------------------------- | ------------------------------------------- |
| `ai-task-brief-writer`     | 用户说"起一个任务" / "写一份 AI 任务说明"   |
| `commit-message-formatter` | 准备提交 / 校验 commit message 时           |
| `phase-gate-runner`        | 跑阶段门检查时                              |
| `traceability-linker`      | 需要回填 REQ ↔ ADR ↔ Task ↔ Commit 追溯链时 |

### Prompts（用户主动 `/` 触发）

| 命令          | 干什么                                                 |
| ------------- | ------------------------------------------------------ |
| `/new-task`   | 起一个 H5 任务：草稿 + 板上登记，不动代码              |
| `/run-gate`   | 按 phase-gate-checklist 核对当前阶段是否能进下一阶段   |
| `/log-review` | 把会议 / PR 评审誊到 `docs/07-reviews/YYYY-MM-DD-*.md` |
| `/sync-board` | 审计 task-board 与代码 / commit 的对齐，列失同步       |

### Agents（在 Chat 顶部下拉手动切）

| Agent                        | 阶段  | 用途                                       |
| ---------------------------- | ----- | ------------------------------------------ |
| `H1-RequirementsInterviewer` | H1    | 反问把模糊需求转成可评审 `requirements.md` |
| `H1-RepoImpactMapper`        | H1↔H3 | 把已 reviewed 需求映射到真实仓库代码       |
| `H2-ArchitectAdvisor`        | H2    | 起草架构选型 + ADR，每条选型留六字段       |
| `H3-DesignReviewer`          | H3    | 评审详细设计是否可进 H4                    |
| `H4-TestCaseAuthor`          | H4    | 从需求与设计反推测试用例矩阵               |
| `H5-CodingExecutor`          | H5    | 严格按 ai-task-brief 执行编码 + Verify     |
| `H5-CommitAuditor`           | H5    | 校验 commit 六字段，不合格拒合并           |
| `H6-ReleaseNoteWriter`       | H6    | 从 commit-records 抽变更生成 release notes |
| `Hx-DocGardener`             | Hx    | 周期巡检 docs/ 与代码偏离                  |

---

## 7. 常见问题 / 排查 / 升级 / 卸载

### Q1: Copilot 看不到我装的 Agent / Skill / Prompt

- 重启 VS Code 一次（Copilot 启动时才扫 `.github/`）
- 检查文件是否真在 `.github/agents/` / `.github/skills/<name>/SKILL.md` / `.github/prompts/`
- 检查 frontmatter 是否完整（`description` 字段必填）
- 看 Copilot 的 Output Panel（"GitHub Copilot Chat"）有无解析报错

### Q2: 我改了 `.github/copilot-instructions.md`，下次 install 会不会被覆盖？

- 默认行为：install 检测到差异会**问你**（除非传了 `-Force`）
- 如果你想长期 own 这份文件，把它的差异通过 `-NoDelete` 或自己回写 source 模板的方式管理
- 真要彻底脱钩：从 `.harness-engineering/manifest.json` 里删掉这一行，下次 install 不再托管

### Q3: 升级到新版本

```powershell
# 1. 先看新版改了什么
git -C <harness-source-repo> pull
# 2. 重新跑 install（会走 diff 流程）
pwsh -File <harness-source-repo>/install.ps1 -TargetRepo .
```

升级是**非破坏性**的：每个文件 install 都会跟现状 diff，让你逐个决定 keep / overwrite / merge。

### Q4: 一键卸载

```powershell
pwsh -File .\.harness-engineering\uninstall.ps1
```

它读 `manifest.json`，把所有 install 写过的文件 / 目录干净移除。**不会动**你自己改过、不在 manifest 里的文件。

### Q5: 我想看完整安装日志

```powershell
Get-Content .\.harness-engineering\install.log
```

每次 install / uninstall 都会追加一行：时间戳、harness commit、目标列表、文件计数、冲突 / 孤儿数。可作为变更审计来源。

### Q6: 模板改了之后，已存在的产物文档（比如已经写好的 task-board.md）会被 overwrite 吗？

不会。**模板只是"新文档的起点"**。已存在的产物文档完全归你管，install / 模板更新都不动它们。要享受新模板的字段，需要你自己手动 backport 到现有文档里。

---

如对手册本身有疑问或建议，去 [Harness Engineering 源仓库](https://github.com/shuaihuadu/harness-engineering) 提 Issue。
