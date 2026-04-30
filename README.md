# Harness Engineering 规范

版本：v0.1  
状态：试行（条款会在 v1.0 前持续收敛）  
适用范围：使用 AI 参与需求、设计、编码、测试、交付和文档维护的软件工程团队

## TL;DR

- **是什么**：一份将 Harness Engineering 思想落到团队 SDLC 的方法论 + 一组可直接使用的 Agent 提示词与文档模板。
- **为谁写**：在真实项目里和 AI 协作，并希望让交付保持可追溯、可评审、可维护的工程团队与个人开发者。
- **解决什么**：把"AI 写得很快但难以验证 / 难以合并 / 难以维护"的现实问题，转化为一条由文档、评审、测试和提交记录组成的硬轨道。
- **核心模型**：按 Agent **行动时序**划分的三层 Harness——约束层（行动前）/ 反馈层（行动中）/ 质量门禁层（行动后），配套 8 个职责单一的 Agent（H1–H6 + 横切两个）。
- **不是什么**：不是工具，不是 SDK，不依赖特定 IDE 或厂商；与 `AGENTS.md` / `CLAUDE.md` / `copilot-instructions.md` 等运行时机制互补，而非替代。

## 如何使用本仓库

本仓库是**规范型仓库**（specification repo），主体内容即 README 本身。常见使用方式有三种，可单独或组合使用：

1. **作为方法论参考**：通读 README，按 §1–§3 把三层 Harness 与 H1–H6 流程映射到自己团队当前的 SDLC，识别缺口。
2. **作为 Agent 提示词模板**：直接复用 [`agents/`](agents/) 下 8 个 Agent 的 `AGENT.md` + `prompt.md`，按需替换项目专属术语后接入到 Copilot Chat / Claude Code / Cursor / 自建工作流。
3. **作为评审 / 门禁清单**：把 [`templates/phase-gate-checklist.md`](templates/phase-gate-checklist.md) 与 [`templates/review-record.md`](templates/review-record.md) 接入团队的 PR 模板与阶段评审，让规范从纸面落到流程。

> 本规范不强制全部采用。建议从单一痛点切入（例如先落 H4 测试用例 + H5 编码约束），跑通再扩展。

## 仓库结构

```
harness-engineering/
├── README.md                       # 规范主体（你正在阅读的文件）
├── agents/                         # 8 个 Agent 的角色规格与提示词
│   ├── README.md                   # Agent 协作拓扑与 H1–H6 编号说明
│   ├── _shared/                    # 跨 Agent 共享：术语表、I/O 契约、工具词表、模板
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
    └── review-record.md            # 评审记录
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

| 层次       | OpenAI Codex 体系                                                                                      | Anthropic Claude Code 体系                                    |
| ---------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| 约束层     | `AGENTS.md`（多级，作为"目录"而非百科全书）、自定义 Lint、结构测试、分层架构不变式                     | `CLAUDE.md`（及子目录继承）、Skills、Subagents                |
| 反馈层     | 测试 / 构建 / Chrome DevTools MCP / 本地可观测栈（LogQL、PromQL）、Ralph Wiggum 循环（Agent 自审自改） | Plan Mode、测试与截图验证、Subagents 隔离调查                 |
| 质量门禁层 | 自定义 Lint 硬失败、结构测试、后台 doc-gardening Agent、提交者路径限制                                 | Hooks（确定性拦截）、Permission allowlist、Sandbox、Auto Mode |

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

本规范把 SDLC 切分为六个 Harness 阶段：

```text
H1 需求、UI 与交互原型
H2 技术架构选型
H3 详细设计
H4 测试用例设计
H5 AI 编码与自验证
H6 运行验证与文档回写
```

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

H1–H6 各阶段的输入、输出物、必填章节与评审门禁，详见独立文件 [`docs/stages.md`](docs/stages.md)。原 README §4–§9 的章节编号在该文件中保持不变（§4–§9），便于其他 Agent 与文档继续按 `§4.4`、`§6.5`、`§9.6` 等编号交叉引用。

| 阶段 | 主题                | 跳转                                                      |
| ---- | ------------------- | --------------------------------------------------------- |
| H1   | 需求、UI 与交互原型 | [stages.md §4](docs/stages.md#4-h1需求ui-与交互原型阶段)  |
| H2   | 技术架构选型        | [stages.md §5](docs/stages.md#5-h2技术架构选型阶段)       |
| H3   | 详细设计            | [stages.md §6](docs/stages.md#6-h3详细设计阶段)           |
| H4   | 测试用例设计        | [stages.md §7](docs/stages.md#7-h4测试用例设计阶段)       |
| H5   | AI 编码与自验证     | [stages.md §8](docs/stages.md#8-h5ai-编码与自验证阶段)    |
| H6   | 运行验证与文档回写  | [stages.md §9](docs/stages.md#9-h6运行验证与文档回写阶段) |

## 5. 目录规范与 Agent 套件

项目目录推荐结构、`AGENTS.md` 的使用约定、以及随规范附带的 8 个 Agent 套件说明，详见独立文件 [`docs/repo-layout.md`](docs/repo-layout.md)。原 README §10 的章节编号在该文件中保持不变（§10.1、§10.2）。

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

以下反模式取自 Anthropic 官方 Claude Code 最佳实践的常见失效模式，在本规范下同样适用。

- **杂烩会话（kitchen sink）**：在同一会话里串联多个不相关任务，上下文被无关内容填满。修正：不同任务开新会话，使用 `/clear` 或重启。
- **反复纠错（correction loop）**：同一问题超过两次仍未调对，说明上下文已被失败尝试污染。修正：重开会话，把学到的信息写进初始提示中。
- **过量规则文件（over-specified `AGENTS.md` / `CLAUDE.md`）**：规则文件越长，Agent 越会忽略重点。修正：定期修剪，能转成 Hooks / Lint 的规则就不要留在文档里。
- **先信后验缺口（trust-then-verify gap）**：AI 交付看似合理的实现，却未覆盖边界条件。修正：始终给出可运行的验收手段（测试、脚本、截图），无法验证的成果不予合并。
- **无界探索（infinite exploration）**：让 AI 调研"这个库怎么回事"而不设边界，它会通过读取大量无关文件把上下文耗尽。修正：限定调研范围，或派发子 Agent / Subagent 在隔离上下文中完成调研。

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

项目级完成标准见 [`docs/stages.md`](docs/stages.md) §9.6。

## 10. 熵与技术债务 GC

> 该节来自 OpenAI Codex 团队在"Harness engineering"文章中提出的实践经验。在 H6 交付后，AI 代码仓库会随时间产生"状态熵"，需要持续清理。

### 10.1 黄金原则（Golden Principles）

团队应提炼出一组可机械化检查的"黄金原则"，描述项目期望代码库保持的形状：

- 优先使用共享工具包，避免手写重复逻辑
- 在边界始终使用类型验证（parse, don't validate），不凭猜测推送数据形状
- 结构化日志、命名约定、文件大小上限等"品味不变式（taste invariants）"需以 Lint 硬拦截
- 跨层依赖只能沿架构图预设方向，逾越者报错

这些原则需写进 `docs/` 下的权威文档（如 `quality-grade.md`）并同步编码为可执行检查。

### 10.2 定期 GC 任务

建议在仓库中配置定期运行的后台 AI 任务，完成以下事项：

- 扫描代码库与黄金原则的偏离，开启重构 PR
- 扫描 `docs/` 下与代码实际行为不一致的过期文档（doc-gardening），开启修复 PR
- 更新 `docs/06-implementation/exec-plans/tech-debt-tracker.md` 中的未完成项
- 合并选项：质量评级 / quality grade 表可在项目初期仅补充到 `docs/04-detailed-design/` 或 `docs/07-release/` 中

### 10.3 使用原则

- **持续偿还 > 集中重构**：技术债务像高利息贷款，每日少量偿还远优于积压后被迫集中返工。
- **人的品味一次捕获，机器永久执行**：评审心得、重构经验、线上故障复盘，要么转化为 `AGENTS.md` / Skill 里的指导，要么转化为 Lint / Hooks / CI 检查。
- **允许小幅 PR 自动合并**：GC 产出的 PR 如果可以在一分钟内评审完毕，应设置成可自动合并。

## 11. 附录：阶段门禁摘要

| 阶段 | 核心产物                     | 通过标准                                       |
| ---- | ---------------------------- | ---------------------------------------------- |
| H1   | 需求、UI、原型               | 需求清晰，UI 可评审，验收标准明确              |
| H2   | 架构说明、技术选型           | 技术路线可落地，风险有缓解方案                 |
| H3   | 详细设计                     | 数据、接口、文件、配置、日志、部署和监控均明确 |
| H4   | 测试计划、测试用例           | 每个关键文件和核心需求都有测试覆盖             |
| H5   | 代码、测试、提交、执行计划   | 小步实现，测试通过，提交可追溯                 |
| H6   | 最终文档、测试报告、运维资料 | 实现与文档一致，系统可运行可维护               |

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
