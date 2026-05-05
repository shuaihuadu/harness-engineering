# Copilot Instructions

本仓库采用 [Harness Engineering 规范]({{HARNESS_REPO_REF_FROM_GITHUB}}) 作为 AI 协作的工程骨架。下方规则面向 GitHub Copilot，按"目录"原则编写：只列硬约束，详细规则全部指向源文档。

> 项目身份与技术栈以仓库根 `README.md` / `AGENTS.md` 为准，本指令不重复维护，避免漂移。

## 1. 硬约束（不可绕过）

- 所有变更必须能映射到一条 `REQ-NNN`（需求编号）。无对应需求的请求一律先反问，不直接写代码。
- 提交信息必须满足 [`commit-format.instructions.md`](./instructions/commit-format.instructions.md) 的字段要求：`Design / Tests / Verify / Docs / Risk / Task` 六字段齐备。
- 修改源码前先运行 `{{TEST_COMMAND}}`，确保起点干净；提交前再次运行，确认未引入回归。
- 风格检查：`{{LINT_COMMAND}}`，警告视作错误处理。
- `docs/` 是事实来源（source of truth）：先改文档再改代码，不要让代码先于设计落地。
- 不在 `docs/04-detailed-design/` 之外的位置放设计内容；不在 `AGENTS.md` 里复述能用 Lint / Hooks / CI 强制的规则。

## 2. 何时切换到专用 Custom Agent

当前项目已装的 Custom Agent（在 VS Code Copilot Chat 顶部下拉菜单中选择）。Agent 名以 `h<阶段号>-` 开头，对应 [Harness 阶段](`{{HARNESS_REPO_REF_FROM_GITHUB}}/docs/stages.md`) H1–H6：

| 场景               | 使用 Agent             |
| ------------------ | ---------------------- |
| 评审 H3 详细设计   | `h3-design-reviewer`   |
| 反推 H4 测试用例   | `h4-test-case-author`  |
| H5 提交 / 评审 PR  | `h5-commit-auditor`    |
| 其他编码           | 默认 Agent（即本指令） |

> 默认 Agent 下不要尝试代行上述专用 Agent 的工作。专用 Agent 的判定逻辑写在各自的 `*.agent.md` 里，单独运行才能保证机械化。
>
> Harness Engineering 还定义了 `RequirementsInterviewer`、`RepoImpactMapper`、`ArchitectAdvisor`、`CodingExecutor`、`ReleaseNoteWriter`、`DocGardener` 等 Agent 规格，但本项目还未将它们包装为 Custom Agent。需要时可参考 [`{{HARNESS_REPO_REF_FROM_GITHUB}}/agents/`]({{HARNESS_REPO_REF_FROM_GITHUB}}/agents/) 补充并重装。

## 3. 关键文档入口

- 阶段细则：`{{HARNESS_REPO_REF_FROM_GITHUB}}/docs/stages.md`（H1–H6）
- 目录规范：`{{HARNESS_REPO_REF_FROM_GITHUB}}/docs/repo-layout.md`
- 反模式：`{{HARNESS_REPO_REF_FROM_GITHUB}}/README.md` 第 6.4 节
- 项目 ADR：`docs/03-architecture/adr/`

> `{{HARNESS_REPO_REF}}` 默认指向已 vendor 的本地副本（`.harness-engineering/`）；如使用 `-NoVendor` 则指向远端 URL。

## 4. 反模式（出现即拒绝）

照搬 [Harness Engineering 规范 6.4 节]({{HARNESS_REPO_REF_FROM_GITHUB}}/README.md) 的五条："杂烩会话 / 反复纠错 / 过量规则文件 / 先信后验缺口 / 无界探索"。当用户请求触发任一条时，先指出反模式，再给替代做法。
