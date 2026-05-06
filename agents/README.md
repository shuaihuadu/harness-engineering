# Harness Engineering 配套 Agent

本目录提供一组与 [Harness Engineering 规范](../README.md) 配套的 Agent 规格。它们是规范的可执行延伸：让 H1–H6 流程不再只依赖文档约定，而是可以由具体工具（Claude Code、GitHub Copilot、OpenAI Codex、自研 Agent Runtime 等）真实跑起来。

> 本目录下的所有 Agent 均与具体业务无关。任何采用本规范的项目都可以直接复用，必要时再派生项目专属变体。

## 1. 设计原则

- **业务无关**：Agent 只读规范定义的产物（`docs/01-requirements/` ... `docs/07-release/`、`AGENTS.md`、`templates/`），不假设任何业务领域。
- **模型中立**：所有 prompt 不依赖某个模型的特殊能力（thinking 标签、专有工具格式），任何具备工具调用能力的 LLM 都可装载。
- **工具中立**：以纯 Markdown 描述 Agent 规格，需要落到具体工具时再做轻量适配（详见第 5 节）。
- **小步交付**：H1–H6 全阶段共 11 个岗位齐配，每个阶段都有对应的 Agent；横切配 1 个 DocGardener。

## 2. Agent 总索引

| Agent                                                          | 阶段       | Harness 层          | 一句话职责                                                                        |
| -------------------------------------------------------------- | ---------- | ------------------- | --------------------------------------------------------------------------------- |
| [RequirementsInterviewer](./requirements-interviewer/AGENT.md) | H1         | 反馈层              | 接收一句话需求，主动反问以暴露模糊点，产出可评审的 `requirements.md` 草稿         |
| [UISpecAuthor](./ui-spec-author/AGENT.md)                      | H1         | 反馈层              | 反问把 UI 细节逼出来，按 stages.md 4.5 节 10 项产出 `ui-spec` / `user-flow` / `acceptance-criteria` |
| [PrototypeReviewer](./prototype-reviewer/AGENT.md)             | H1         | 质量门禁层          | 只读评审：读 UI 文档 + 原型截图，按 phase-gate H1 那 12 条 PASS/FAIL/UNKNOWN，不写文件 |
| [RepoImpactMapper](./repo-impact-mapper/AGENT.md)              | H1↔H3 之间 | 约束层              | 在做计划前扫描真实代码，产出可审核的"仓库影响地图"，拦截"AI 凭空编 API"的失败模式 |
| [ArchitectAdvisor](./architect-advisor/AGENT.md)               | H2         | 反馈层 + 约束层     | 反问补齐架构约束、对备选项机械化打分，产出 `architecture.md` / 选型 / 风险 / ADR  |
| [DesignReviewer](./design-reviewer/AGENT.md)                   | H3         | 质量门禁层          | 机械化校验详细设计的完备性与一致性，挡住"设计没写清"流入 H4/H5                    |
| [TestCaseAuthor](./test-case-author/AGENT.md)                  | H4         | 反馈层              | 从需求与设计反推 `TC-NNN`，确保每条 REQ 至少有可机械判断的覆盖                    |
| [CodingExecutor](./coding-executor/AGENT.md)                   | H5         | 反馈层              | 严格按 `ai-task-brief.md` 完成单个工程单元，同步生成测试与提交元数据              |
| [CommitAuditor](./commit-auditor/AGENT.md)                     | H5/H6      | 质量门禁层          | 在 PR / 合并前机械化校验提交信息、改动范围、追溯字段                              |
| [ReleaseNoteWriter](./release-note-writer/AGENT.md)            | H6         | 反馈层              | 从 commit-records 与追溯链生成 release notes 草稿，回写追溯矩阵                   |
| [DocGardener](./doc-gardener/AGENT.md)                         | 跨阶段     | 质量门禁层 + 反馈层 | 定时巡检 `docs/` 与代码实际行为的偏离，开具修复 PR                                |

后续候选（仍按"避免缺乏真实样本时过早设计"原则保留）：

- IncidentResponder（H6 之后的故障复盘辅助）

## 3. 协作拓扑

```text
H1: RequirementsInterviewer ──► UISpecAuthor ──► PrototypeReviewer ──► RepoImpactMapper
                                                                              │
H2:                                                                    ArchitectAdvisor
                                                                              │
H3:                                                                    DesignReviewer
                                                                              │
H4:                                                                    TestCaseAuthor
                                                                              │
H5:                                                                    CodingExecutor ──► CommitAuditor ──► CI 钩子 / 项目专属 Linter
                                                                                                                  │
H6:                                                                                                               └──► ReleaseNoteWriter

横切（定时 / Webhook 触发）：DocGardener
```

### 3.1 交接约定

上图箭头不是函数调用，是**文档落地交接**。所有 Agent 遵守同一条规则：

- Agent 之间**不直接调用**对方。每个 Agent 只读自己上游产出的文档、写自己负责的产物，下游何时启动由人工或调度器决定。
- 单个 Agent 发现需要其它 Agent 介入时，按 [`_shared/io-contracts.md`](./_shared/io-contracts.md) 的「阻塞返回」结构输出 `status: blocked` + 具体缺口，**不要**自行扩张职责把下游的活也干了。
- 共享文档落点固定：`docs/01-requirements/` / `docs/04-detailed-design/` / `docs/05-test-design/` / `docs/06-implementation/exec-plans/` / `docs/07-release/`。每个 Agent 的 `AGENT.md` 已显式声明它读哪些路径、写哪些路径。

这条约定让流水线图在工具维度可解释——人工调度器、CI 钩子、Copilot 下拉菜单切换 Agent，三种触发方式底下走的是同一条契约。

## 4. 共享契约

所有 Agent 共用以下两份契约文件，避免每个 `AGENT.md` 重复定义：

- [`_shared/glossary.md`](./_shared/glossary.md)：阶段编号、产物路径、追溯字段等术语统一定义。
- [`_shared/io-contracts.md`](./_shared/io-contracts.md)：输入输出文件命名、frontmatter 字段、提交信息格式、错误返回结构。
- [`_shared/tool-vocabulary.md`](./_shared/tool-vocabulary.md)：Agent 工具能力共享词表，由各 `AGENT.md` 的工具集引用。
- [`_skeletons/AGENT.skeleton.md`](./_skeletons/AGENT.skeleton.md) / [`_skeletons/prompt.skeleton.md`](./_skeletons/prompt.skeleton.md)：新增 Agent 时使用的干净骨架。

## 5. 通用 Skills（跨 Agent 的可复用 SOP）

[`_skills/`](./_skills/README.md) 下提供若干**操作型 Skill**：被多个 Agent 反复用到的元动作（追溯、写任务卡、写提交信息、阶段门禁核对）。它们与 Agent 是不同的事物——Agent 是一个角色，Skill 是一段可重入的流程。

| Skill                                                                   | 解决的问题                                               |
| ----------------------------------------------------------------------- | -------------------------------------------------------- |
| [traceability-linker](./_skills/traceability-linker/SKILL.md)           | 校验并补全 `REQ ↔ HD/API/DB ↔ TC ↔ TASK ↔ Commit` 追溯链 |
| [ai-task-brief-writer](./_skills/ai-task-brief-writer/SKILL.md)         | 把口头需求/Issue 转成合规 H5 任务卡                      |
| [commit-message-formatter](./_skills/commit-message-formatter/SKILL.md) | 按六字段模板生成或校验提交信息                           |
| [phase-gate-runner](./_skills/phase-gate-runner/SKILL.md)               | 按阶段门禁清单逐条核对                                   |

新增 Skill 的判断标准与目录约定见 [`_skills/README.md`](./_skills/README.md)。

## 6. 接入具体工具

每个 Agent 只交付两份纯 Markdown 文件：

- `AGENT.md`：Agent 规格（定位、触发、输入输出、行为约束、验收标准）。
- `prompt.md`：模型中立的中文系统提示。

> 这两份文件是公共核心：业务规则只在这里维护一次。Copilot、Codex、Claude Code 等工具在 [`_integrations/`](./_integrations/README.md) 下各占一个子目录，仅做识别 / 调用 / 权限三类入口适配，不复制业务、不为单一工具改写规则。完整设计思路见 [`_integrations/README.md` 第 0 节](./_integrations/README.md#0-设计思路)。

落到具体工具时只需做一层轻量包装：

| 工具                          | 包装方式                                                                                                           |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Claude Code                   | 在 `.claude/agents/<name>.md` 加 frontmatter（`name`、`description`、`tools`、`model`），正文 `@` 引用 `prompt.md` |
| GitHub Copilot Chat           | 在 `.github/agents/<name>.agent.md` 配置工具集（VS Code 1.118+ Custom Agents），正文引用 `prompt.md`               |
| OpenAI Codex / AGENTS.md 体系 | 在 `AGENTS.md` 子目录指向对应 `AGENT.md`，由 Runtime 注入 `prompt.md`                                              |
| 自研 Agent Runtime            | 直接读取 `AGENT.md` 的输入输出契约 + `prompt.md` 作为 system prompt                                                |

> **不要**把工具特有的 frontmatter 写进 `AGENT.md` / `prompt.md` 自身。包装文件可以放在使用方仓库（如 `.claude/`、`.github/`），保持本目录的工具中立。

可直接复用的模板见 [`_integrations/`](./_integrations/README.md)，覆盖 Claude Code、GitHub Copilot Chat、OpenAI Codex、自研 Runtime 四类落地方式。

## 7. 版本与演进

- 当前版本：v0.0.1（与仓库根 [`VERSION`](../VERSION) 一致）
- 状态：试行

### 7.1 修改门槛

`prompt.md` / `AGENT.md` 的修改属于规范级变更，按以下门槛执行：

- **轻微修订**（错别字、格式、链接、不改行为）：直接 PR，1 名维护者评审即可
- **行为微调**（措辞改变 Agent 行为但不改契约）：必须附 1 个真实项目的反例，并在 PR 描述中给出修改前后 Agent 的输出对比
- **契约变更**（修改 `AGENT.md` 输入输出、工具集、阻塞返回条件）：必须先在本目录第 7 节登记修订建议，由维护者批量回写

### 7.2 反例采集

每个 Agent 在落地后保留以下输入用于演进：

- 触发阻塞返回的真实输入（脱敏后存入项目内部知识库）
- 产出与规范要求偏离的真实案例
- 评审会中被人工驳回的产物

数量门槛：单个 Agent 累计 ≥ 3 个反例后，才允许提出"行为微调"级别的 PR。

### 7.3 何时新增 Agent

提出新 Agent 前必须先回答：

1. 该职责是否能用现有 Agent + 不同输入完成？若是，**不要**新增
2. 该职责是否真的需要独立系统提示？还是仅在 `AGENT.md` 加一节"工作流变体"即可？
3. 是否已有至少一个真实项目跑出了"缺这个 Agent"的具体卡点？没有就是空想，押后

通过以上三问后，再按 [`_skeletons/AGENT.skeleton.md`](./_skeletons/AGENT.skeleton.md) 与 [`_skeletons/prompt.skeleton.md`](./_skeletons/prompt.skeleton.md) 起草。

### 7.4 退役

允许把 Agent 标记为 `deprecated`：

- `AGENT.md` 顶部加 `> **状态**：deprecated（自 vX.Y 起）`
- 在本目录第 2 节索引表中标灰（不删除条目）
- 给出迁移建议（指向继任 Agent 或人工流程）

退役至少保留两个版本周期再考虑物理删除。

## 8. 对规范的修订建议（占位）

落地 Agent 过程中如果发现规范本身需要调整，集中记录到本节，由维护者批量回写到 [`../README.md`](../README.md)。每条建议格式：

```markdown
- **触发 Agent**：<哪个 Agent 在落地中发现>
- **规范章节**：<README.md 的 X.Y>
- **问题**：<具体描述>
- **建议**：<修改方向>
- **证据**：<反例 / 链接>
```

当前为空。

## 9. 调度纪律：路由者不做专业判断

本规范没有引入"中央 PM Agent"。流程的接力由人工或调度脚本（`docs/06-tasks/task-board.md` 维护者、CI 钩子、IDE 下拉切换）担任，统称**调度者**。调度者必须遵守一条硬纪律：

- **只做路由，不做专业判断**：调度者读各 Agent 的产物结论（含 `status: blocked`），决定下一棒由谁接手，不替任何 Agent 给专业意见（不补需求、不改方案、不替开发拍板）
- **不替下游解释上游**：调度者不允许"我觉得这条阻塞可以忽略"。`status: blocked` 一旦出现，要么打回上游，要么进任务看板的"等待人工决策"
- **不绕过质量门禁**：调度者不得跳过 [`templates/phase-gate-checklist.md`](../templates/phase-gate-checklist.md) 中的检查项以"赶进度"
- **路由理由可审计**：每次跨阶段切换、每次回退都要在评审记录或任务看板留下一行"谁、何时、依据哪份产物"

为什么单独立这一节：调度者站在所有阶段的中央，天然知道每个 Agent 在干什么，也最容易越界把"流程协调者"滑成"流程总专家"。一旦越界，整套多 Agent 体系会被悄悄拉回"一个中央大脑说了算"的旧结构，前面拆角色的所有努力都会失效。
