# 输入输出契约

本文件定义所有 Agent 共用的 I/O 契约。每个 `AGENT.md` 引用本文件而非重复定义。

## 1. 文件路径与编码

- 所有产物文件使用 **UTF-8 NoBOM** 编码。
- 行尾统一为 `LF`（项目级 `.editorconfig` 兜底）。
- 路径一律使用相对仓库根的正斜杠形式，如 `docs/01-requirements/requirements.md`。
- Agent 工具能力名一律取自 [`tool-vocabulary.md`](./tool-vocabulary.md)。

## 1.1 事实源 vs 导出物

Harness Engineering 中的文档分两类，谁可被下游 Agent 读取是硬约束：

| 类别       | 定义                                                      | 下游 Agent / Skill 可读？                        |
| ---------- | --------------------------------------------------------- | ------------------------------------------------ |
| **事实源** | 由某个 Agent / 人工产出，有 `status` 字段可被评审扣上签名 | 可读（且需验证 `status ≥ reviewed`）             |
| **导出物** | 从事实源机械合并而来，`status: generated`，不可独立编辑   | **不可读**——仅服务人类受众（对外、评审会、汇报） |

全局禁令：任何 Agent / Skill **不得**在 `AGENT.md` 输入契约里列出以下路径，也不得在运行时主动 fetch：

- `docs/01-requirements/PRD.md`（由 `prd-exporter` Skill 导出，源于同目录下四件事实源 `requirements.md` / `ui-spec.md` / `user-flow.md` / `acceptance-criteria.md`）

未来新增导出类 Skill 时，需在本表追加一行，同时在该 Skill 的 `SKILL.md` 顶部带必要的 banner。

为什么这样设：

- 导出物是某一时刻的快照；让下游 Agent 读快照 = 绕过事实源的评审门禁、且一旦源文件更新而未重导会读到过期信息
- 事实源拆成多件是有意设计（各自独立评审、变更影响面可控）；导出物是“为人类受众拼一下”，不应被机器反向消费
- 单一事实源原则：同一条信息只能从一个入口被读到，避免版本漂移

## 2. Markdown frontmatter 约定

需要被 Agent / 工具自动消费的 Markdown 文档应在文件首部加 YAML frontmatter：

```yaml
---
id: REQ-001                    # 编号，见 glossary.md 第 4 节
stage: H1                      # 所属阶段
status: draft                  # draft / reviewed / approved / deprecated
authors:
  - name: <人或 Agent 名>
    role: human | agent
reviewers:                     # 进入 reviewed 状态后填写
  - <reviewer>
created: 2026-04-27
updated: 2026-04-27
upstream:                      # 上游依赖产物
  - REQ-000
downstream: []                 # 下游消费产物（由后续阶段回填）
---
```

未列出的字段允许扩展，但不得改变上述字段的语义。

## 3. 编码任务说明（H5 输入）

H5 任务说明在 `templates/ai-task-brief.md` 基础上必须填齐以下字段：

- `当前阶段`：固定 `H5`
- `任务编号`：`TASK-YYYY-MM-DD-NNN`
- `允许修改的文件`：完整路径列表
- `禁止修改的文件`：完整路径列表
- `上游文档`：需求 / UI / 架构 / 详细设计 / 测试用例的文件路径或编号
- `设计引用`：`HD-xxx`、`API-xxx`、`DB-xxx`
- `测试引用`：`TC-xxx`
- `验收命令`：可执行的测试 / 构建命令

## 4. 提交信息约定

```text
<type>(<scope>): <summary>

Design: HD-xxx
Tests: TC-xxx, TC-yyy
Verify: <可复现的命令行>
Docs: updated | not needed
Risk: none | <简述>
Task: TASK-YYYY-MM-DD-NNN
```

`<type>` 取值：`feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `perf` / `build` / `ci`。

`Design` / `Tests` / `Task` 三字段是追溯链的核心，缺失任意一项视为提交不合规，CommitAuditor 会拒绝。

## 5. Agent 错误返回结构

当 Agent 因输入不满足前置条件而无法继续时，**必须**返回结构化错误，而非凭空补全。建议格式：

```yaml
status: blocked
reason: <简短原因，如 "REQ-001 未通过评审">
missing_inputs:
  - path: docs/01-requirements/requirements.md
    expected_status: approved
    actual_status: draft
suggested_next_action:
  - 完成 H1 评审并将 frontmatter status 改为 approved
  - 或在任务说明中显式声明降级处理理由
```

### 5.1 用户收到 `blocked` 之后怎么办

`blocked` 不是死路。它是一份"现场报告"，告诉你下一步去哪儿补凭证。固定动作：

1. 把 Agent 返回的 `suggested_next_action` 整段贴到 `docs/06-tasks/task-board.md` 第 2 节"等待人工决策（Pending）"，附本次会话的时间戳。这样不至于过几天再回来时忘了卡在哪。
2. 按 `missing_inputs` 列出的 `path` / `expected_status` 反向去补——大多数情况落在 H1（status 没签）/ H3（设计没写完）/ H4（缺 TC）。需要切对应阶段的 Agent 时去 [`docs/stages/`](../../docs/stages/README.md) 找入口。
3. 上游补完之后，**新开一个 chat 窗口**重跑原任务，**不要复用旧的会话上下文**——旧会话里残留的"我已经试过 X"会污染新会话的判断。
4. 如果 `suggested_next_action` 看不懂或者你判断它有问题，去 [Harness Engineering 源仓库](https://github.com/shuaihuadu/harness-engineering) 提 Issue，**不要硬绕过去**——绕过 = 把架空凭证带进下游评审。

## 6. 上下文卫生约定

- **禁止**在单次会话中跨阶段操作（如同一会话先做 H1 又做 H5）。
- **禁止**在不引用上游产物路径的情况下进行实现。
- **建议**：探索性查阅交给 subagent / 隔离会话，避免污染主会话上下文。
- **建议**：会话中"常驻加载"的规范类文件（AGENTS.md / 单个 AGENT.md / 当前阶段的 stages 节选）总行数尽量控制在 ~600 行以内。背景：Anthropic 的工程实践表明上下文窗口填充率超过 40% 后，模型输出质量（幻觉、循环、Tool Call 格式错误）快速衰退；项目级文档应做成"按需查阅"而非"一次喂饱"。
- **建议**：`AGENTS.md` 是索引（Index & Map），不是百科全书。超过 100 行就考虑把内容拆到 `docs/` 下，由 `AGENTS.md` 提供跳转。

## 6.1 交互式输入约定（PICK OVER TYPE）

本节规定 **运行时**（会话进行中）Agent 向用户拿信息的形式约束。与 [第 7 节](#7-人工输入位约定human-input)（**离线时**写到文件里的占位行）互补：

- §6.1：Agent 在 chat 里**当场问**用户 → "能选就别让填"
- §7：Agent 把**留给人离线填**的位置标成 `> **[ 待填 ]**：...`

> 工具能力维度上，本节规则全部归属 [`tool-vocabulary.md`](./tool-vocabulary.md) 第 1 节的 `ask.user`。在 Copilot / VS Code 集成层映射为 `vscode/askQuestions`；在其他集成层（Claude Code / Codex 等）映射为各自的等价交互能力。Agent 的 `AGENT.md` 一律只声明 `ask.user`，集成层负责落地。

### 决策矩阵

| 字段类型               | 例子                                                                                          | 形式约束                                                                |
| ---------------------- | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| **封闭枚举**           | `status` / `stage` / `卡点等级` / `priority` / `severity` / `结论`（PASS/FAIL/UNKNOWN） | **必须** picker（`ask.user` + `options[]`），**禁止** 自由文本通道       |
| **半结构化**           | `reviewer` / `主持人` / `决策人` / `日期` / `version` / `tag` / `commit 区间` / 文件路径    | **必须** picker；候选项从下方"默认值检测"产出；末尾留 `自由输入` 兜底     |
| **预枚举候选答**       | `open-questions.md` 里 OQ-NNN 的 A/B/C/D                                                    | **必须** picker（A/B/C/D + 自定义），不要在 chat 里让用户回复 "A"       |
| **自由 prose**         | 业务诉求复述 / 设计理由 / 风险描述 / 不做范围说明 / 验收提示                                | **保持** chat 文本反问；**禁止** 强行做成 picker（picker 装不下长说明） |

### 默认值检测规则（半结构化字段）

Agent 在问之前**必须**先尝试检测候选值，再把检测结果作为 `options[]` 给出。"先猜、再让用户改"比"空白让用户从零写"快一个数量级。

| 字段                            | 检测来源                                                                                |
| ------------------------------- | --------------------------------------------------------------------------------------- |
| reviewer / 主持人 / 决策人 / 记录人 | `git config user.name`；补充 `git log --format=%an \| sort -u \| head -10`                |
| 日期（today / yesterday）       | 本地系统时钟                                                                            |
| version / tag                   | 仓库根 `VERSION` 文件（若存在）；`git tag --sort=-creatordate \| head -3`                 |
| commit 区间                     | `git log --oneline -20`，让用户分别选起 / 止                                              |
| 文件路径                        | `read.search.text` / 项目内 file_search                                                 |
| 关联编号（REQ-NNN / TASK-NNN） | `read.search.text` 全仓 grep frontmatter id                                              |

检测到的值放进 `options[]`；末尾**始终**保留一项 `自由输入` 或 `其他（请显式给出）`，避免封死特殊场景。

### 合并规则（避免对话疲劳）

属于同一逻辑动作的多个字段，**必须**合并到 **一次** `ask.user` 调用（一次工具调用，多个 `questions[]`），**禁止**串成 N 个连续对话框。

| 逻辑动作                      | 合并后字段                                                  |
| ----------------------------- | ----------------------------------------------------------- |
| 评审记录抬头                  | 项目 / 阶段 / 评审对象 / 时间 / 主持人 / 记录人 / 参与人员（≤ 7 项） |
| OQ-NNN 关闭                   | 回答 / 决策日期 / 决策人（3 项）                              |
| Commit metadata 收集          | Design / Tests / Verify / Docs / Risk / Task（6 项）          |
| Status 翻转                   | 旧 status / 新 status / reviewer / decision / date（5 项）     |

> 单次 `ask.user` 调用的总问题数受 [第 9 节"反问澄清单次问答上限 5 个"](#9-循环与迭代上限) 约束；超过时拆成两次调用，但**禁止**把同一逻辑动作的强相关字段拆开。

### 反模式（出现即拒绝）

- 把封闭枚举字段做成 `请输入 status（draft / reviewed / approved）`——这是文本通道，不是 picker
- 在 chat 里列 `A. ... B. ... C. ...` 然后说"请回复 A 或 B"——应该用 picker 的 `options[]`
- 把同一份逻辑表单的 6 个字段拆成 6 次 `ask.user` 调用
- 把自由 prose 字段（"复述你理解的核心诉求"）强塞进 picker
- Agent 自己用 `git config` 等命令拿到默认值后**不让用户确认**就直接写到文件里——必须把检测值作为 picker 默认项，让用户一键确认或改
- 对**评审决议 / 阶段门通过与否 / status 翻转**等"人工兜底"字段预填默认值或设 `recommended`——picker 必须无 default、无 recommended，由人显式选；AI 不替人下决心。这条是 [第 7 节"人工输入位约定"](#7-人工输入位约定human-input) 的对应硬约束

## 7. 人工输入位约定（HUMAN INPUT）

Agent 起草产物时，凡是**需要人工填答 / 决策 / 签字**的位置，**必须**显式标记为可视化占位行，不能默认空白或用 `<TBD>` 蒙混。统一格式：

```markdown
> **[ 待填 ]**：<提示语，告诉用户应该写什么>
```

适用场景：

| 场景                                                           | 谁产出                       | 人工要做什么                                                                                                                                                                                                                                |
| -------------------------------------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `open-questions.md` 每条 OQ 的 **回答 / 决策日期 / 决策人** 行 | 起草 Agent（H1 / H2 各阶段） | 把 `> **[ 待填 ]**：...` 整行替换成你的实际答案；模板见 [`templates/open-questions.md`](../../templates/open-questions.md)                                                                                                                  |
| frontmatter `reviewers: []`                                    | 起草 Agent                   | `/log-review` 后人工按本文件第 2 节示例追加一行（`name / role / decision / date`）                                                                                                                                                          |
| frontmatter `status: draft`                                    | 起草 Agent                   | 评审通过后人工改 `draft → reviewed`；本规范禁止 Agent 自行修改文档 frontmatter 的 `status` 字段（依据 [`tool-vocabulary.md`](./tool-vocabulary.md) 第 2 节"最小授权"原则——任何 Agent 的 `write.file` / `write.patch` 能力都不应覆盖此字段） |
| `phase-gate-checklist.md` 表格"结论"列                         | `/run-gate` Agent            | 全 PASS 之后人工把 `[ ]` 勾成 `[x]`，再切下一阶段                                                                                                                                                                                           |
| `risk-analysis.md` 的"残余风险接受"列                          | `H2-ArchitectAdvisor`        | 人工签字接受残余风险（无人签 = 不能进 H3）                                                                                                                                                                                                  |
| `AGENTS.md` 第 1 节"项目身份" / 第 4 节"模块边界 / 禁区"       | 不由 Agent 起草              | 项目负责人亲手签字（任何 Agent 起草都视作越权）；具体填法由对应集成层手册说明                                                                                                                                                               |

约束：

- **可视化优先**：用 `> **[ 待填 ]**：...` 这种 blockquote + 粗体方括号的醒目形式。**禁用** HTML 注释占位（用户在渲染视图下看不见），**禁用** `<TBD>` / "待定" / 空字符串。
- **每个 placeholder 自带提示语**：告诉用户"具体要写什么"——例如 `> **[ 待填 ]**：YYYY-MM-DD`、`> **[ 待填 ]**：选 A / B / C / 自定义，附 1 句理由`。
- **替换粒度 = 一整行**：人工填答时**整行替换** `> **[ 待填 ]**：...`，不要在原行后面追加。这样 grep `\[ 待填 \]` 能立刻列出"还有哪些位置等我"。
- **Agent 不替人工填**：任何标了 `[ 待填 ]` 的位置，Agent 不得自行补全；缺信息时按第 5 节 `blocked` 返回，并在 `suggested_next_action` 里指出"哪份文件的哪行需要人工填"。

## 8. 不做范围

以下行为不属于任何 Agent 的职责，不得在 `AGENT.md` 里被赋予：

- 直接合并 PR（必须由人工或独立 CI 系统完成）
- 直接发布制品（H6 之后的发布动作不在本规范的 Agent 体系内）
- 修改本目录下的规范文件（`.he/README.md` 与本目录下任何 `AGENT.md` / `prompt.md`）

## 9. 循环与迭代上限

Agent 的"反问 / 改稿 / 评审 / 自修复"循环必须有硬上限，超出后返回 `blocked`（第 5 节），不得继续。这是为了避免两类故障：Agent 陷入无限自我修改、用户在多轮拉扯中失去方向。

| 场景                                           | 单次会话上限      | 超限后的处理                                                                            |
| ---------------------------------------------- | ----------------- | --------------------------------------------------------------------------------------- |
| Reviewer Agent 反复打回（H1 评审 / H3 评审）   | 3 轮              | 返回 `blocked`，`suggested_next_action` 写明"问题已收敛到 X 条但未达成共识，需人工裁决" |
| 编码评审 / 测试评审打回（H5 范围内）           | 2 轮              | 返回 `blocked`，列出仍未通过的检查项                                                    |
| Agent 同一文件的"自修复"重试（如测试失败重写） | 3 次              | 不再继续重试，返回真实失败输出，由人工裁决降级 / 改设计 / 接受失败                      |
| 反问澄清（H1-Interviewer 等问答型 Agent）      | 单次问答 5 个问题 | 一次性问完，等用户答完再继续；禁止"边问边猜"                                            |

约束：

- 上限触发前，Agent 必须把"已尝试方案 / 仍未解决的具体点"写进返回，而不是只说"卡住了"。
- 上限触发后，Agent **禁止**自行降低验收标准或绕过门禁字段（如把 status 直接改 reviewed）来逃出循环。
- 对一类反复触发上限的场景，应当回写到 `tech-debt-tracker.md` 或 `repo-impact-map.md`，下一轮规则迭代时优先处理——避免同一种打回反复消耗用户时间。

