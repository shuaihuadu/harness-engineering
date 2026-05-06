# Harness Engineering · 操作手册（HANDBOOK）

**10 分钟读完即可上手。** 涵盖：每个目录放了什么、什么时候切哪个 Agent、什么时候打哪条 `/` 命令、模板怎么改、要卸载或升级怎么办。

---

## 目录

1. [装完后该干啥（按项目状态分流）](#1-装完后该干啥按项目状态分流)
2. [全流程一览：H1 → H6 + Hx](#2-全流程一览h1--h6--hx)
3. [`.github/` 里都装了什么](#3-github-里都装了什么)
4. [`.harness-engineering/` 里都装了什么](#4-harness-engineering-里都装了什么)
5. [Templates 怎么用、怎么改](#5-templates-怎么用怎么改)
6. [Skills / Prompts / Agents 速查](#6-skills--prompts--agents-速查)
7. [常见问题 / 排查 / 升级 / 卸载](#7-常见问题--排查--升级--卸载)

---

## 1. 装完后该干啥（按项目状态分流）

先看你属于哪种情况，再决定从哪进门：

| 你的状态 | 入口 |
| --- | --- |
| **全新空仓 / 项目还没启动 / 还没有任何 `REQ-NNN`** | 走 [1.1 节：全新项目从 H1 起步](#11-全新项目从-h1-起步) |
| **老仓改造 / 给已有项目加一个具体小功能（已有 REQ/HD 凭证）** | 走 [1.2 节：已有项目从 H5 起跳](#12-已有项目从-h5-起跳) |

> 关键概念：`/new-task` 是 **H5（编码）的入口，不是项目的入口**。它把"已有 REQ/HD"切成可执行的代码改动；空仓没有 REQ 可指，它会反问 / 阻塞返回。**别用 `/new-task` 起新项目**——切 Agent 才是。

### 1.1 全新项目从 H1 起步

依次切 Agent 跑下去，每一步的产出会成为下一步的输入；不要跳级，跳级会让追溯链断在你身上。

1. **H1 需求**：Copilot Chat 顶部 Agent 下拉切到 `h1-requirements-interviewer`，用一段大白话描述目标用户、核心场景、必做与可选——它会反问、追问、把回答落成 `docs/01-requirements/requirements.md` 草稿，分配 `REQ-001`、`REQ-002`…，没答清的进 `open-questions.md`，**不会自动用 `<TBD>` 占位**。
2. **（可选）H1 影响图**：切 `h1-repo-impact-mapper`。全新空仓基本是全部新建，可跳过；老仓改造时它会列出受影响的模块 / 文件 / 接口 / 测试。
3. **H2 架构 / ADR**：切 `h2-architect-advisor`。它基于上一步的 requirements 给一份初版架构（项目划分、技术栈、依赖关系）+ 关键 `ADR-NNN`（每条含"选择 / 为什么 / 替代 / 放弃理由 / 维护成本 / 性能-安全-交付影响"六字段）。这一步决定源码树长什么样、用什么栈。
4. **H3 详细设计**：人手起草 `docs/04-detailed-design/<feature>/HD-NNN.md`（接口、数据模型、错误码、并发与失败语义）。写完切 `h3-design-reviewer` 让它逐项核对完备性，挡住"设计还没写清"流入下一阶段。
5. **H4 测试用例**：切 `h4-test-case-author`。它从 REQ + HD 反推 `docs/05-test-design/test-cases.md`（每条 `TC-NNN`），保证每个 `REQ-NNN` 都有至少一条机械可判断的覆盖。
6. **H5 起任务 → 编码 → 审提交**：上游凭证齐全后，就可以走 [1.2 节](#12-已有项目从-h5-起跳) 那四步把每条任务跑完。
7. **H6 发版说明**：版本切出来时切 `h6-release-note-writer`，从 commit 抽取生成 `docs/07-release/release-notes.md`，回写追溯矩阵。

> 第 1 步产出的 `requirements.md` 是后面所有阶段的"上游凭证"——commit message 里的 `Design: REQ-001` / `Tests: TC-NNN` / `Task: TASK-NNN` 都是顺着它往下挂的。**没有这一步，提交格式校验会一路把你打回来**。

### 1.2 已有项目从 H5 起跳

仓库已经有 `docs/01-requirements/requirements.md`（或等价的需求凭证），这次只想加一个具体的小功能，跟着这四步把最小闭环跑一遍：

1. **起一个最小任务**：在 Copilot Chat 输入 `/new-task` 加你想做的小事；首次运行它会按模板自动建 `docs/06-tasks/task-board.md`，并起草 `docs/06-tasks/T-001-xxx.md`、同时登记一行到看板。
2. **人工审任务说明**：核对 `允许修改的文件` 与 `Verify 命令` 是否合理；OK 之后把 `docs/06-tasks/task-board.md` 里这一行的 `status` 改成 `ready`。
3. **切到 `H5-CodingExecutor`**：在 Copilot Chat 顶部的 Agent 下拉里选它，让它按任务说明执行。
4. **提交前切到 `H5-CommitAuditor`**：让它逐字段校验 commit message（Design / Tests / Verify / Docs / Risk / Task）。

> 中小变更允许跳过 H1–H4 直接从 H5 起跳，但底线是：**每个 commit 至少要能映射到一条 `REQ-NNN`**。如果这次改动连 REQ 都对不上，先回 1.1 节第 1 步把 requirements 补齐再来——`H5-CommitAuditor` 不会替你豁免这条。

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

并不强制把 H1 → H6 全走完才能动手——分流规则见 [第 1 节](#1-装完后该干啥按项目状态分流)：全新项目按 1.1 节老老实实从 H1 起步；老仓加小功能按 1.2 节从 H5 起跳，事后补 `requirements.md` 链路。

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

**这 25 个文件全部开箱即用，不用再做任何配置：进 Copilot Chat，直接选 Agent / 输 `/` 即可。**

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

这个目录承担两件事：**随时能查规范文档**（HANDBOOK + docs/），以及**能干净卸载**（manifest + uninstall.ps1）。安装完成后它不需要你再去改——所有自定义都应该发生在 `.github/` 里。

如果觉得它和项目本身无关、不想入版本库，**推荐把它加进 `.gitignore`**：

```gitignore
.harness-engineering/
```

代价：团队其他人 `git pull` 后看不到这份手册，需要自己再跑一次 `install.ps1`。如果想让所有人都能直接读，就保留入版本库。

---

## 5. Templates 怎么用、怎么改

`.github/templates/` 里 4 个文件是**产物的初始骨架**，分两种用法：

### 5.1 直接复制使用

需要在仓库里建一个新文档（比如手工起草一份任务简报）：

```powershell
# 例：从模板初始化任务简报
New-Item -ItemType Directory -Path docs\06-tasks -Force | Out-Null
Copy-Item .github\templates\ai-task-brief.md docs\06-tasks\T-001-<slug>.md
```

然后按里面的注释自己填。

> 任务看板 `task-board.md` 不需要手工复制——`/new-task` 首次运行会自动建到 `docs/06-tasks/task-board.md`。

### 5.2 让 Agent / Prompt 引用

四条 `/` 命令背后都会读模板：

| Slash 命令    | 读取的模板                                            |
| ------------- | ----------------------------------------------------- |
| `/new-task`   | `ai-task-brief.md`；首次运行同时按 `task-board.md` 模板自动建 `docs/06-tasks/task-board.md` |
| `/run-gate`   | `phase-gate-checklist.md`                             |
| `/log-review` | `review-record.md`                                    |

所以你改完 `.github/templates/*.md` 之后：

- 直接复制使用的人，下一次复制就拿到新版
- AI 执行 Prompt 时也会读到新版
- **不需要重启 VS Code，不需要重跑 `install.ps1`**

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

- 重启一次 VS Code（Copilot 只在启动时扫描 `.github/`）
- 确认文件确实在 `.github/agents/` / `.github/skills/<name>/SKILL.md` / `.github/prompts/`
- 检查 frontmatter 是否完整，`description` 字段必填
- 翻一下 Output Panel 的 "GitHub Copilot Chat"，看有没有解析报错

### Q2: 我改了 `.github/` 下的某个文件，下次 install 会被覆盖吗？

不会自动覆盖。`install.ps1` 拿你本地版本与 manifest 里登记的 `sha256` 比对，发现差异就**逐个弹**四选一：

```
[O]verwrite  /  [K]eep  /  [A]ll-overwrite  /  a[B]ort
```

- 选 `K`：保留本地改动，本次跳过
- 选 `O`：用新版覆盖
- 选 `A`：本次后续所有冲突一律覆盖
- 选 `B`：中断本次 install

只有传 `-Force` 才会全部静默覆盖。想长期 own 某个文件，每次升级时按 `K` 即可；想彻底脱钩、连询问都不要，从 `.harness-engineering/manifest.json` 里删掉对应那一行。

### Q3: 升级到新版本

```powershell
# 1. 拉取新版本
git -C <harness-source-repo> pull
# 2. 重新跑 install
pwsh -File <harness-source-repo>/install.ps1 -TargetRepo .
```

升级是**非破坏性**的：未改过的文件直接同步，已改过的文件按 Q2 的四选一逐个询问；新版本里删掉的文件会作为孤儿询问是否清理（不想清就加 `-NoDelete`）。

### Q4: 一键卸载

```powershell
pwsh -File .\.harness-engineering\uninstall.ps1
```

按 `manifest.json` 反向移除全部装过的文件。本地改过的文件默认**保留**并打 `keep` 标记，加 `-Force` 才会一并删除；不在 manifest 里的文件全程不动。

### Q5: 我想看完整安装日志

```powershell
Get-Content .\.harness-engineering\install.log
```

每次 install / uninstall 追加一行：时间戳 / harness commit / 目标列表 / 文件计数。可作为变更审计来源。

### Q6: 模板更新后，已经写好的产物文档（比如现有的 `docs/06-tasks/task-board.md`）会被覆盖吗？

不会。**模板只是新文档的起点**。已存在的产物文档完全归你管，install 与模板更新都不会动它们；想用上新模板的字段，需要自己手动 backport。

---

对手册本身有疑问或建议，去 [Harness Engineering 源仓库](https://github.com/shuaihuadu/harness-engineering) 提 Issue。
