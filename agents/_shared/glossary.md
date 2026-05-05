# 共享术语表

本文件统一定义本目录下所有 Agent 引用的术语，避免每个 `AGENT.md` 重复定义。所有术语与 [Harness Engineering 规范](../../README.md) 的章节保持同步。

## 1. 阶段术语

> 编号 `H1`–`H6` 中的 `H` 取自 *Harness*，`Hn` 是 **Harness Stage n**（Harness 阶段 n）的缩写。即 `H1 = Harness Stage 1`、`H2 = Harness Stage 2`，依此类推到 `H6 = Harness Stage 6`。完整定义与"约束层 / 反馈层 / 质量门禁层"的正交关系见 [`../../README.md` 第 3 节](../../README.md#3-标准流程)。

| 编号 | 中文名              | 英文名                               | 主要产物目录                                                 |
| ---- | ------------------- | ------------------------------------ | ------------------------------------------------------------ |
| H1   | 需求、UI 与交互原型 | Requirements, UI & Prototype         | `docs/01-requirements/`、`docs/02-prototype/`、`prototypes/` |
| H2   | 技术架构选型        | Technical Architecture Selection     | `docs/03-architecture/`                                      |
| H3   | 详细设计            | Detailed Design                      | `docs/04-detailed-design/`                                   |
| H4   | 测试用例设计        | Test Case Design                     | `docs/05-test-design/`                                       |
| H5   | AI 编码与自验证     | AI Coding & Self-Verification        | `docs/06-implementation/`                                    |
| H6   | 运行验证与文档回写  | Runtime Verification & Doc Writeback | `docs/07-release/`                                           |

## 2. 三层 Harness

按 Agent **行动时序**划分的三个切面（与 H1–H6 阶段编号是正交关系）：

- **约束层（Constraint Harness）—— 行动前**：通过 `AGENTS.md`、`copilot-instructions.md`、Lint、类型系统等前馈控制缩小 Agent 解空间。
- **反馈层（Feedback Loop）—— 行动中**：通过测试、构建、运行结果向 Agent 回灌结构化信号。
- **质量门禁层（Quality Gate）—— 行动后**：在 CI / 评审 / 合并环节硬拦截不合规产物。

## 3. 关键产物

| 产物         | 路径                                                     | 用途                               |
| ------------ | -------------------------------------------------------- | ---------------------------------- |
| 顶层规则     | `AGENTS.md`                                              | Agent 规则的"目录"，限 100 行内    |
| 任务说明     | `templates/ai-task-brief.md` 派生                        | H5 单次编码任务的输入              |
| 编码任务索引 | `docs/06-implementation/coding-tasks.md`                 | H5 任务总索引                      |
| 提交记录     | `docs/06-implementation/commit-records.md`               | 提交→设计→测试映射                 |
| 执行计划     | `docs/06-implementation/exec-plans/active/<task-id>.md`  | 跨多个设计项的复杂任务计划         |
| 技术债务     | `docs/06-implementation/exec-plans/tech-debt-tracker.md` | 已知技术债务追踪                   |
| 追溯矩阵     | `docs/07-release/traceability-matrix.md`                 | 需求→设计→代码→测试→提交的最终追溯 |

## 4. 编号约定

| 前缀    | 含义                                 | 示例                  |
| ------- | ------------------------------------ | --------------------- |
| `REQ-`  | 需求项                               | `REQ-001`             |
| `UI-`   | UI 项                                | `UI-007`              |
| `ADR-`  | 架构决策记录                         | `ADR-003`             |
| `HD-`   | 详细设计项（High-level Design item） | `HD-042`              |
| `API-`  | 接口设计项                           | `API-005`             |
| `DB-`   | 数据库设计项                         | `DB-012`              |
| `TC-`   | 测试用例                             | `TC-128`              |
| `TASK-` | H5 编码任务                          | `TASK-2026-04-21-001` |

编号一旦发布即视为不可变，废弃项标记 `[Deprecated]` 而不是删除编号。

## 5. 评审结论

- `Approved`：通过，可进入下一阶段
- `Approved with Changes`：小修改后可进入下一阶段
- `Rejected`：不通过，必须返工
- `Pending`：信息不足，暂缓决策

## 6. 角色与载体

本规范区分四种"约束怎么落地"的载体，不可混用（详见 [`../../README.md` 第 6.5 节](../../README.md#65-软约束的失败模式与处置阶梯)）：

| 载体                 | 性质     | 适用约束                                                                                                                                    |
| -------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Scripts / Hooks / CI | 硬约束   | 编译、测试、Lint、命名、文件大小、追溯字段等可机械判定项                                                                                    |
| Rule                 | 软约束   | 设计取舍、架构原则等不能机械判定项；落在 `AGENTS.md` / `instructions/` / Agent prompt                                                       |
| Skill                | 操作脚本 | 跨 Agent 复用的多步流程（追溯检查、任务卡生成、提交信息格式校验等）                                                                         |
| Memory               | 个人偏好 | 工具侧"记忆层"（Claude Code Memory / Copilot User Memory / Cursor Rules-for-User），仅作单人会话偏好，不进入团队规范（见 README 第 6.6 节） |

并列三个**实体概念**：

- **Agent**：本规范定义的 8 个职责单一角色（`requirements-interviewer` / `design-reviewer` / ...），落在 `agents/<name>/AGENT.md` + `prompt.md`。
- **Skill**：跨 Agent 复用的操作型 SOP，落在 `agents/_skills/<name>/SKILL.md`，有标准化 frontmatter 与触发条件。
- **Custom Agent**：AI 编码工具（Copilot / Cursor / Claude Code 等）侧的"会话级 Agent"装载方式，把上述 Agent 的 prompt 包装成工具自家的配置文件（如 `.github/agents/*.agent.md`）。Agent 是规范概念，Custom Agent 是工具落地形态。
