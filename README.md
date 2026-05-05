# Harness Engineering 规范

版本：v0.0.1  
状态：试行（条款会在 v1.0 前持续收敛）  
适用范围：使用 AI 参与需求、设计、编码、测试、交付和文档维护的软件工程团队

## TL;DR

- **是什么**：一份将 Harness Engineering 思想落到团队 SDLC 的方法论 + 一组可直接使用的 Agent 提示词与文档模板 + 一套把它们一键铺到你仓库的脚本。
- **为谁写**：在真实项目里和 AI 协作，并希望让交付保持可追溯、可评审、可维护的工程团队与个人开发者。
- **解决什么**：把"AI 写得很快但难以验证 / 难以合并 / 难以维护"的现实问题，转化为一条由文档、评审、测试和提交记录组成的硬轨道。
- **核心模型**：按 Agent **行动时序**划分的三层 Harness——约束层（行动前）/ 反馈层（行动中）/ 质量门禁层（行动后），配套 8 个职责单一的 Agent（H1–H6 + 横切两个）。

### 这是什么 / 不是什么

| 这是                                                                                           | 这不是                                                                |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 一份**团队 AI 工程规约**：文档结构 + 评审节奏 + Agent 角色定义                                 | AI Agent 框架 / SDK / 运行时（不替代 LangGraph、Agent Framework 等）  |
| 一套**多工具分发器**：同一份角色定义可同步成 Copilot Custom Agent / Claude Code subagent / ... | 一键万能解（Custom Agent 是"打开才用"，没有团队文化基础时就是死代码） |
| **可被采纳为 standard 的规范**：`.harness-engineering/` 目录直接提交进你的仓库                 | prompt 库（提供的是结构与契约，不是预制 prompt 的集合）               |
| 与 `AGENTS.md` / `copilot-instructions.md` / `CLAUDE.md` 等运行时机制**互补**                  | 自动化质量门禁（CI / Hooks / Lint 仍需各项目自行接入）                |

> **设计取向**：业务规则集中在 [`agents/`](agents/README.md) 一份维护，Copilot、Codex、Claude Code 等工具仅在 [`agents/_integrations/`](agents/_integrations/README.md) 下各自占据一个入口子目录，对同一份公共核心做格式包装。完整设计思路见 [`agents/_integrations/README.md` 第 0 节](agents/_integrations/README.md#0-设计思路)。

## 快速开始

仓库根 `install.ps1` / `install.sh` 把规范文档 vendor 进你的项目并为指定的 AI 编码工具渲染配置：

```powershell
# Windows / 跨平台（PowerShell 7+）
git clone https://github.com/shuaihuadu/harness-engineering.git
cd harness-engineering
./install.ps1 -TargetRepo D:\Path\To\YourRepo
```

```bash
# Linux / macOS（依赖 jq）
./install.sh --target-repo /path/to/your/repo
```

默认会做四件事：

1. **Vendor 规范文档**到 `<your-repo>/.harness-engineering/`
2. **渲染 Copilot 配置**到 `.github/copilot-instructions.md` + `.github/instructions/*`
3. **不默认安装 Custom Agent**：必须显式 `-CopilotAgents commit-auditor,...` 或 `-CopilotAgents all`
4. **写入安装清单**到 `<your-repo>/.harness-engineering/manifest.json`，供 `uninstall` 使用并在重装时自动预填

完整选项（占位符策略、Vendor / NoVendor 模式、卸载方式、多 target）见 [`docs/install.md`](docs/install.md)。

## 如何使用本仓库

本仓库是**规范型仓库**（specification repo），主体内容即 README 本身。常见使用方式有三种，可单独或组合使用：

1. **作为方法论参考**：通读 README，按第 1–3 节把三层 Harness 与 H1–H6 流程映射到自己团队当前的 SDLC，识别缺口。
2. **作为 Agent 提示词模板**：直接复用 [`agents/`](agents/) 下 8 个 Agent 的 `AGENT.md` + `prompt.md`，按需替换项目专属术语后接入到 Copilot Chat / Claude Code / Cursor / 自建工作流。
3. **作为评审 / 门禁清单**：把 [`templates/phase-gate-checklist.md`](templates/phase-gate-checklist.md) 与 [`templates/review-record.md`](templates/review-record.md) 接入团队的 PR 模板与阶段评审，让规范从纸面落到流程。

> 本规范不强制全部采用。建议从单一痛点切入（例如先落 H4 测试用例 + H5 编码约束），跑通再扩展。

## 仓库结构

```
harness-engineering/
├── README.md                       # 规范主体（你正在阅读的文件）
├── install.{ps1,sh}                # 一键集成脚本（详见 docs/install.md）
├── uninstall.{ps1,sh}              # 卸载脚本
├── docs/                           # 细则与扩展手册
│   ├── stages.md                   # H1–H6 阶段细则
│   ├── repo-layout.md              # 目录规范与项目级索引（dev-map）
│   ├── install.md                  # 安装、占位符、Vendor / NoVendor 模式
│   └── tech-debt-gc.md             # 黄金原则、定期 GC、使用原则
├── agents/                         # 8 个 Agent 的角色规格与提示词
│   ├── README.md                   # Agent 协作拓扑、交接约定与调度纪律
│   ├── _shared/                    # 跨 Agent 共享：术语表、I/O 契约、工具词表、模板
│   ├── _skills/                    # 跨 Agent 复用的操作型 Skill
│   ├── _integrations/              # 与 Copilot / Claude Code / Cursor / AGENTS.md 的对接说明
│   ├── requirements-interviewer/   # H1 需求访谈
│   ├── repo-impact-mapper/         # H1 代码库影响分析
│   ├── design-reviewer/            # H3 设计评审
│   ├── test-case-author/           # H4 测试用例
│   ├── coding-executor/            # H5 编码执行
│   ├── commit-auditor/             # H5 提交审计
│   ├── release-note-writer/        # H6 发布说明
│   └── doc-gardener/               # 横切：文档治理
└── templates/                      # 可直接复制使用的工作产物模板
    ├── ai-task-brief.md            # AI 任务简报（H5 入口）
    ├── phase-gate-checklist.md     # 阶段门禁清单
    ├── review-record.md            # 评审记录
    └── task-board.md               # 项目任务看板（需求侧"从哪进门"索引）
```

每个 Agent 目录均包含：`AGENT.md`（角色定位、输入输出、工作约束）+ `prompt.md`（可直接投喂给 LLM 的系统提示词）。

## 1. 总览

### 1.1 概念背景

Harness Engineering（中文社区暂无官方译名，本规范采用"驾驭工程"，与 OpenAI 标语 "Humans steer" 同源）这一术语在 2026 年 2 月由 Mitchell Hashimoto 在其个人博客中首次提出，并由 OpenAI（Ryan Lopopolo）在 2026 年 2 月 11 日发布的文章中给出正式定义。LangChain 把它精炼为一个公式：**Agent = Model + Harness**，OpenAI 给出的标语是 **"Humans steer. Agents execute."（人类掌舵，Agent 执行）**。

业界对 Harness Engineering 的共识定义是：

> 设计环境、约束和反馈回路，让 AI 编码 Agent 在规模化场景下保持可靠的工程学科。

本规范在此基础上按 Agent **行动时序**展开为三层（约束层 / 反馈层取自社区共识，质量门禁层引自 DevOps 词汇，三者按"行动前 / 行动中 / 行动后"分工，避免按机制划分时的归属重叠）：

- **约束层（Constraint Harness）—— 行动前**：规则文件、Lint、类型系统、AGENTS.md / copilot-instructions.md 等前馈控制，缩小 Agent 的解空间。
- **反馈层（Feedback Loop）—— 行动中**：把测试、Lint、构建错误等结构化信号回灌给 Agent，让其自我修复。
- **质量门禁层（Quality Gate）—— 行动后**：在 CI、评审、合并环节进行硬性拦截，阻止不合规产物进入主干。

主流工具厂商对这三层的落地可作为对照：

| 层次       | GitHub Copilot 体系                                                                                                                                        | OpenAI Codex 体系                                                                                      | Anthropic Claude Code 体系                                    |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| 约束层     | `.github/copilot-instructions.md`、`.github/instructions/*.instructions.md`（带 `applyTo` 模式）、`AGENTS.md`、`.github/agents/*.agent.md`（Custom Agent） | `AGENTS.md`（多级，作为"目录"而非百科全书）、自定义 Lint、结构测试、分层架构不变式                     | `CLAUDE.md`（及子目录继承）、Skills、Subagents                |
| 反馈层     | Agent Mode（`#codebase` / `#fetch` / 终端 / Problems 回灌）、MCP 工具集成、Copilot Edits 多文件迭代                                                        | 测试 / 构建 / Chrome DevTools MCP / 本地可观测栈（LogQL、PromQL）、Ralph Wiggum 循环（Agent 自审自改） | Plan Mode、测试与截图验证、Subagents 隔离调查                 |
| 质量门禁层 | Copilot code review（PR 阶段）、Branch protection + Required reviewers、Secret scanning push protection、GitHub Actions CI                                 | 自定义 Lint 硬失败、结构测试、后台 doc-gardening Agent、提交者路径限制                                 | Hooks（确定性拦截）、Permission allowlist、Sandbox、Auto Mode |

本规范作为上述体系中 **"文档化 + SDLC"** 这一层的通用骨架，与底层工具不冲突。

### 1.2 本规范的定位

本规范是上述思想在 **"团队 SDLC + AI 协作"** 场景下的一份具体落地方案，重点放在**约束层和质量门禁层的人工与文档化部分**：用文档、评审、测试和提交记录构成一条 Agent 在工作时必须遵守的硬轨道。它**不试图覆盖**所有运行时层面的 Harness（如 Lint 钩子、CI 拦截、运行时工具调度），这些应由具体项目的 CI/CD 流水线、`AGENTS.md` / `copilot-instructions.md` 等配套机制实现。

一句话定位：

> 本规范是 Harness Engineering 在 SDLC 维度的人工版骨架——用文档、评审、测试、提交和运行回写，把 AI 的创造力约束成可交付、可追溯、可维护的软件工程能力。

## 2. 核心原则

### 2.1 先说明，后实现

任何编码工作开始前，必须先完成需求说明、UI 说明、架构说明、详细设计和测试用例设计。

如果某项内容无法清晰说明，就不应进入编码阶段。

### 2.2 AI 生成，人类审核

AI 可以参与以下工作：

- 梳理需求
- 设计 UI 和用户流程
- 生成可交互 UI 原型
- 推演技术架构
- 生成详细设计
- 设计测试用例
- 编写代码和测试代码
- 运行测试并自我修复
- 修订文档

但每个关键阶段必须由团队审核。AI 的输出不能直接替代评审结论。

### 2.3 文档即约束

通过评审的 Markdown 文档是后续阶段的工作依据。

AI 编码时，必须严格引用已评审文档中的需求、设计、接口、数据结构、测试用例和验收标准。

### 2.4 测试先于代码

编码前必须先定义测试用例。测试用例应覆盖正常路径、异常路径、边界条件、权限边界、数据一致性和关键性能约束。

### 2.5 小步编码，小步提交

每次只让 AI 完成一个明确的工程单元。每个工程单元必须完成代码、测试、运行验证和提交记录。

推荐粒度：

- 一个程序文件及其测试
- 一个 API 端点及其测试
- 一个数据库迁移及其验证
- 一个配置项及其验证
- 一个后台任务及其测试
- 一个前端组件及其交互测试

### 2.6 运行结果回写文档

系统真实运行后，必须根据实际实现、测试结果、部署记录和运行日志修订需求、设计、测试、运维和用户说明文档。

## 3. 标准流程

本规范把 SDLC 切分为六个 **Harness 阶段**，编号 `H1`–`H6` 中的 `H` 取自 *Harness*，`Hn` 即 **Harness Stage n** 的缩写（如 `H1 = Harness Stage 1`，依此类推到 `H6`）。每个阶段在时间上前后衔接，但与第 1.1 节的"约束层 / 反馈层 / 质量门禁层"是正交关系：阶段是**时序切片**，层是**性质切片**，同一阶段内可以同时落多种层的产物。

| 编号 | 中文名               | 英文名                              | 一句话定位                                                  |
| ---- | -------------------- | ----------------------------------- | ----------------------------------------------------------- |
| H1   | 需求、UI 与交互原型  | Requirements, UI & Prototype        | 把业务想法转成可评审的需求说明、UI 说明与可交互原型         |
| H2   | 技术架构选型         | Technical Architecture Selection    | 形成可落地的架构图与技术选型，并给出风险与缓解              |
| H3   | 详细设计             | Detailed Design                     | 数据、接口、文件、配置、日志、部署、监控逐项落到可读设计稿  |
| H4   | 测试用例设计         | Test Case Design                    | 把需求与设计翻译为单元 / 集成 / 端到端用例清单              |
| H5   | AI 编码与自验证      | AI Coding & Self-Verification       | 由 AI 在任务卡约束下小步实现，跑通测试与 Lint 后小步提交    |
| H6   | 运行验证与文档回写   | Runtime Verification & Doc Writeback| 真实运行后回写需求 / 设计 / 测试 / 运维 / 用户说明文档      |

阶段编号 H1–H6 与文档目录 `01–07` 的映射关系如下（H1 同时产出需求和原型两类目录，因此目录数比阶段数多 1）：

| 阶段 | 文档目录                                                                   |
| ---- | -------------------------------------------------------------------------- |
| H1   | `docs/01-requirements/` + `docs/02-prototype/` + `prototypes/`（原型源码） |
| H2   | `docs/03-architecture/`                                                    |
| H3   | `docs/04-detailed-design/`                                                 |
| H4   | `docs/05-test-design/`                                                     |
| H5   | `docs/06-implementation/`（任务清单与提交记录）                            |
| H6   | `docs/07-release/`                                                         |

每个阶段都必须满足：

- 输入清晰
- 输出完整
- 假设明确
- 风险记录
- 评审通过
- 可支撑下一阶段

## 4. 阶段细则（H1–H6）

H1–H6 各阶段的输入、输出物、必填章节与评审门禁，详见独立文件 [`docs/stages.md`](docs/stages.md)。该文件以第 4–9 节编号展开，其他 Agent 与文档可按 `第 4.4 节`、`第 6.5 节`、`第 9.6 节` 等编号交叉引用。

| 阶段 | 主题                | 跳转                                                           |
| ---- | ------------------- | -------------------------------------------------------------- |
| H1   | 需求、UI 与交互原型 | [stages.md 第 4 节](docs/stages.md#4-h1需求ui-与交互原型阶段)  |
| H2   | 技术架构选型        | [stages.md 第 5 节](docs/stages.md#5-h2技术架构选型阶段)       |
| H3   | 详细设计            | [stages.md 第 6 节](docs/stages.md#6-h3详细设计阶段)           |
| H4   | 测试用例设计        | [stages.md 第 7 节](docs/stages.md#7-h4测试用例设计阶段)       |
| H5   | AI 编码与自验证     | [stages.md 第 8 节](docs/stages.md#8-h5ai-编码与自验证阶段)    |
| H6   | 运行验证与文档回写  | [stages.md 第 9 节](docs/stages.md#9-h6运行验证与文档回写阶段) |

## 5. 目录规范与 Agent 套件

项目目录推荐结构、`AGENTS.md` 的使用约定、以及随规范附带的 8 个 Agent 套件说明，详见独立文件 [`docs/repo-layout.md`](docs/repo-layout.md)（该文件以第 10 节编号展开，可按 `第 10.1 节`、`第 10.2 节` 引用）。

## 6. AI 使用规范

### 6.1 AI 输入必须明确

每次让 AI 工作时，必须提供：

- 当前阶段
- 目标产物
- 已通过评审的上游文档
- 不允许修改的范围
- 输出格式
- 验收标准
- 需要重点检查的风险

### 6.2 AI 输出必须可审计

AI 输出必须满足：

- 可审阅
- 可追溯
- 可执行
- 可测试
- 可回滚
- 不引入未确认需求
- 不隐藏假设

### 6.3 AI 禁止直接编码的情况

以下情况不得要求 AI 直接编码：

- 需求未评审
- UI 未评审
- 架构未评审
- 详细设计未完成
- 测试用例未定义
- 文件职责不清
- 接口契约不清
- 数据结构不清
- 验收标准不清

### 6.4 AI 使用反例

以下反模式取自社区积累的常见失效模式，在本规范下同样适用。

- **杂烩会话（kitchen sink）**：在同一会话里串联多个不相关任务，上下文被无关内容填满。修正：不同任务开新会话，使用 `/clear` 或重启。
- **反复纠错（correction loop）**：同一问题超过两次仍未调对，说明上下文已被失败尝试污染。修正：重开会话，把学到的信息写进初始提示中。
- **过量规则文件（over-specified `AGENTS.md` / `CLAUDE.md`）**：规则文件越长，Agent 越会忽略重点。修正：定期修剪，能转成 Hooks / Lint 的规则就不要留在文档里。
- **先信后验缺口（trust-then-verify gap）**：AI 交付看似合理的实现，却未覆盖边界条件。修正：始终给出可运行的验收手段（测试、脚本、截图），无法验证的成果不予合并。
- **无界探索（infinite exploration）**：让 AI 调研"这个库怎么回事"而不设边界，它会通过读取大量无关文件把上下文耗尽。修正：限定调研范围，或派发子 Agent / Subagent 在隔离上下文中完成调研。
- **完成幻觉（completion illusion）**：Agent 自报"已完成 / 已验证 / 已通过"，但实际只是流程往前推进了，并没有客观判定结果是否正确。修正：完成定义只能由可执行检查给出，不接受 Agent 主观汇报；对应到 H5，就是"验收命令必须有输出留痕"，见第 11 节附录。
- **Rule 解释性绕过（rule rationalization）**：Agent 知道规则存在，但用"这次场景特殊 / 是历史遗留 / 我已做等价验证"等理由跳过执行。修正：能机械判定的规则一律下沉为脚本或 Lint，不要停留在自然语言层；不能下沉的规则使用阻塞返回（见 [`agents/_shared/io-contracts.md` 第 5 节](agents/_shared/io-contracts.md)），由人工拍板，不允许 Agent 自行豁免。
- **下游回改上游（cross-stage overwrite）**：下游 Agent 觉得上游产物不严谨，直接修改上游文档而不是退回上游。修正：下游只允许提出阻塞项，由人工/调度器把流程退回上游；产物归属边界见 [`agents/README.md` 第 3.1 节](agents/README.md#31-交接约定)。

### 6.5 软约束的失败模式与处置阶梯

Rule 是软约束：再清晰的自然语言，在长上下文与复杂需求下都会被忽略或解释性绕过。把"约束怎么生效"和"约束放在哪里"分两件事看，可以更稳：

| 约束性质                                                 | 首选载体                                  | 失败兜底                            |
| -------------------------------------------------------- | ----------------------------------------- | ----------------------------------- |
| 能机械判定（编译、测试、Lint、命名、文件大小、追溯字段） | **Scripts / Hooks / CI**                  | 失败即阻断合并；不接受自然语言豁免  |
| 可判定但代价高（涉及外部系统、需人审）                   | **质量门禁层 + 评审记录**                 | 阻塞返回 + 评审记录留痕             |
| 不能机械判定（设计取舍、架构原则）                       | **Rule（`AGENTS.md` / `instructions/`）** | 写进 prompt + Skill；评审时人工把关 |
| 个人偏好（语种、shell、排版习惯）                        | **个人 Memory / 工具私有配置**            | 不进入团队规范，不依赖跨人对齐      |

判断口径：**如果一条规则在第二次被绕过时还只能靠"再加一句话"治理，它就该下沉一层载体。**

### 6.6 团队真相落仓库，个人偏好留 Memory

很多 AI 编码工具都提供"记忆层"（Claude Code 的 CLAUDE.md / Memory、Copilot 的用户 Memory、Cursor 的 Rules-for-User 等）。这层能力本身没有问题，但在多人协作的团队 Harness 里，**它不能成为团队约束的权威来源**：

- **可以**：单人偏好（回答语种、常用 shell、个人快捷指令）、临时调试便签、当前会话的上下文片段
- **不可以**：编码规范、提交格式、评审清单、追溯字段、阶段产物的命名约定，以及任何"两个人会因为说法不一致而吵架"的规矩

判断口径：

> **凡是可能被新人接手、可能被审计、可能影响交付质量的事实与规则，都必须落到 `docs/`、`agents/`、`AGENTS.md` 或 Scripts 里——它们能被 diff、被 review、被 CI 看见；记忆层做不到这三件事。**

错题集与故障复盘特别要警惕：如果只在私人 Memory 里堆"上次踩过的坑"，下次换一个人或换一个会话就重新踩。重要的反例必须晋升一层——能机械判定的进 Scripts，不能机械判定的进 Rule，并且都要有 commit 记录。

## 7. 评审规范

每个阶段评审必须保留记录，建议使用 `templates/review-record.md`。

评审记录应包括：

- 评审时间
- 参与人员
- 评审对象
- 通过项
- 修改项
- 风险项
- 结论
- 下一步动作

评审结论分为：

- `Approved`：通过，可进入下一阶段
- `Approved with Changes`：小修改后可进入下一阶段
- `Rejected`：不通过，必须返工
- `Pending`：信息不足，暂缓决策

## 8. 追溯关系

本规范要求所有交付物之间建立完整的追溯关系：

```text
需求 -> UI/原型 -> 架构 -> 详细设计 -> 测试用例 -> 代码/配置 -> 提交 -> 测试报告 -> 部署/运维文档
```

这条链最终沉淀为 `docs/07-release/traceability-matrix.md`，由 H5 阶段维护的 `commit-records.md` 汇总而成。

每个代码文件应能回答：

- 它来自哪个需求？
- 它实现哪个设计项？
- 它对应哪些测试用例？
- 它由哪个提交引入？
- 它是否已在最终文档中体现？

## 9. 质量标准

一个阶段只有在满足以下条件时，才视为完成：

- 输出物完整
- 关键假设明确
- 风险已记录
- 评审已通过
- 修改意见已处理
- 与上游文档一致
- 可支撑下一阶段工作

项目级完成标准见 [`docs/stages.md`](docs/stages.md) 第 9.6 节。

## 10. 熵与技术债务 GC

> 在 H6 交付后，AI 代码仓库会随时间产生"状态熵"，需要持续清理。该实践经验来自 OpenAI Codex 团队在 *Harness engineering* 一文中提出的方案。

核心要点：

- **黄金原则**：每个团队应提炼一组可机械检查的代码形状不变式（共享工具优先、边界类型验证、跨层依赖方向、文件大小、命名约定等），并以 Lint / CI 硬拦截
- **定期 GC**：配置后台 AI 任务扫描代码偏离与文档过期，开重构 / 修复 PR；对应 Agent 落点见 [`agents/doc-gardener/AGENT.md`](agents/doc-gardener/AGENT.md)
- **持续偿还 > 集中重构**：一次评审捕获的品味，要么进 `AGENTS.md` / Skill，要么进 Lint / Hooks / CI；不要堆在脑子里
- **小幅 PR 自动合并**：GC 产出可一分钟评完的 PR 应允许自动合并

完整黄金原则示例、GC 任务清单与使用原则见 [`docs/tech-debt-gc.md`](docs/tech-debt-gc.md)。

关于团队真相 vs 个人 Memory 的边界，见 [第 6.6 节](#66-团队真相落仓库个人偏好留-memory)。

## 11. 附录：阶段门禁摘要

| 阶段 | 核心产物                     | 通过标准                                                   |
| ---- | ---------------------------- | ---------------------------------------------------------- |
| H1   | 需求、UI、原型               | 需求清晰，UI 可评审，验收标准明确                          |
| H2   | 架构说明、技术选型           | 技术路线可落地，风险有缓解方案                             |
| H3   | 详细设计                     | 数据、接口、文件、配置、日志、部署和监控均明确             |
| H4   | 测试计划、测试用例           | 每个关键文件和核心需求都有测试覆盖                         |
| H5   | 代码、测试、提交、执行计划   | 小步实现，测试通过，提交可追溯，开发前后基线对比无新增违规 |
| H6   | 最终文档、测试报告、运维资料 | 实现与文档一致，系统可运行可维护                           |

## 12. 参考资料

本规范在设计中参考了以下公开资料：

- OpenAI · [*Harness engineering: leveraging Codex in an agent-first world*](https://openai.com/index/harness-engineering/)（Ryan Lopopolo，2026-02-11）
- OpenAI Cookbook · [*Codex Execution Plans*](https://cookbook.openai.com/articles/codex_exec_plans)
- Anthropic · [*Best Practices for Claude Code*](https://code.claude.com/docs/en/best-practices)
- Anthropic · [*Claude Code Memory（CLAUDE.md）*](https://code.claude.com/docs/en/memory)
- Anthropic · [*Claude Code Skills*](https://code.claude.com/docs/en/skills)
- [AGENTS.md 跨工具开放约定](https://agents.md/)（2025-08）
- LangChain Blog · [*The Anatomy of an Agent Harness*](https://blog.langchain.com/the-anatomy-of-an-agent-harness/)
- Mitchell Hashimoto · [*My AI Adoption Journey*](https://mitchellh.com/writing/my-ai-adoption-journey)
- Red Hat Developers · [*Harness engineering: Structured workflows for AI-assisted development*](https://developers.redhat.com/articles/2026/04/07/harness-engineering-structured-workflows-ai-assisted-development)（Marco Rizzi，2026-04-07）
- Augment Code · [*Harness Engineering for AI Coding Agents: Constraints That Ship Reliable Code*](https://www.augmentcode.com/guides/harness-engineering-ai-coding-agents)（2026-04-16）

## 协议与引用

本规范以**开放共享**为原则，欢迎任何团队、个人在自有项目中借鉴、改写或派生。

- **协议**：建议按 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.zh) 共享文档内容，按 [MIT](https://opensource.org/licenses/MIT) 共享 `agents/` 与 `templates/` 中的提示词与模板代码。仓库根目录的 `LICENSE` 文件以最终版本为准。
- **引用**：如在博客、白皮书或公开演讲中引用本规范，建议注明：
  > Harness Engineering 规范（驾驭工程），v0.1，<https://github.com/shuaihuadu/harness-engineering>
- **派生**：派生版本请保留对原仓库的引用，并在派生说明中标注差异点。

## 贡献

本规范处于试行阶段，欢迎以下形式的贡献：

- 在真实项目中落地后，反馈条款的可执行性与缺口（Issue）
- 提交针对具体 Agent 提示词、模板、术语表的修订（Pull Request）
- 补充新的工具厂商对照（OpenAI / Anthropic 之外的 Cursor、Factory、Augment 等）

提交前请阅读 [`templates/phase-gate-checklist.md`](templates/phase-gate-checklist.md)，确保改动本身也满足本规范的最小自一致要求（变更说明、影响范围、是否需要同步更新 Agent 与术语表）。
