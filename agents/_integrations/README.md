# 工具包装模板

本目录提供把 [`agents/`](../README.md) 下中立 Agent 接入具体 IDE / Runtime 的**模板**。模板本身不是规范的一部分——使用方按需复制到自己的仓库 / 工作区，再做项目化调整。

> 设计原则：保持 `agents/<name>/AGENT.md` 与 `prompt.md` 工具中立。任何工具特有的 frontmatter、文件位置、权限配置都放在本目录的模板里，而不是污染 Agent 自身。

## 0. 设计思路

Harness Engineering 与具体 AI 编码工具之间的关系，是**单一公共核心 + 多工具入口**：所有 Agent 的角色边界、输入输出契约、工作流和 SOP 都集中在 [`agents/`](../README.md) 维护一份；Copilot、Codex、Claude Code、自研 Runtime 等工具只在本目录下各自占一个子目录，把同一份核心翻译成它们能识别的入口格式。

```text
                  agents/<name>/AGENT.md
                  agents/<name>/prompt.md
                  agents/_shared/*
                  agents/_skills/<name>/SKILL.md
                          │
                          │ 工具中立的角色契约 + 工作流 + SOP
                          │ 任何采用方都直接复用，不为某个工具改写
                          ▼
            ┌─────────────┼─────────────┬─────────────┐
            ▼             ▼             ▼             ▼
       copilot/        codex/      claude-code/    generic/
       Custom Agent  AGENTS.md      .claude/      runtime
       + instructions 片段         agents/       config
            │             │             │             │
            └─────────────┴─────────────┴─────────────┘
                          │
                          ▼
              仓库根 install.ps1 / install.sh
              把上述模板渲染并同步到采用方仓库
```

读这张图的方式只有一条线索：**业务规则向上汇聚，工具差异向下扩散**。

### 核心与入口的边界

业务规则只在公共核心维护一次。`AGENT.md` 给出角色定位、触发条件、输入输出契约；`prompt.md` 给出工作流和判断标准；`_shared/` 给出跨 Agent 共享的术语、I/O 契约、工具词汇；`_skills/` 给出可被多个 Agent 复用的元动作。任何工具来接入，都不应该让这些文件为它单独让步。

入口模板只关心三件事：让目标工具识别得到、调用得起来、不越权。具体到产物，就是 frontmatter（`description` / `tools` / `model` 等）、落地路径（`.github/agents/` / `.claude/agents/` / `AGENTS.md`）、以及对原文的引用方式（`@` 引用 / include / 占位符替换）。模板里没有业务流程，只有让公共核心被正确装载所必需的最小外壳。

由此带来的几条硬约束，落地时反复出现：

- 适配模板**不复制** `AGENT.md` / `prompt.md` 的正文。需要让模型读到原文，就用工具自身支持的引用机制；不支持引用的工具，就由安装器在渲染时拼装，并保留来源注释。
- 适配模板**不承担业务变更**。如果发现需要调整 Agent 的行为或契约，回到 [`agents/<name>/`](../README.md) 改源；改完一次，所有工具入口下次重装即同步。
- 适配模板**不混入项目业务约束**。某个项目专属的代码规范、模块边界、命名规则属于采用方仓库自己的 `.github/instructions/` 或 `AGENTS.md`，由项目按文件作用域装载，不进本目录。
- **新增工具先包再改**。要支持新的 IDE 或 Runtime，第一选择是在本目录加一个新的子目录，把同一份 `AGENT.md` / `prompt.md` 翻译成它的格式；只有公共契约本身存在表达力不足时，才允许回头修改 `agents/<name>/`。

### 升级路径

公共核心一处改，所有入口下次重装时统一生效。采用方仓库不需要逐工具维护多份分叉；维护者也不会面对"改一条规则要同步五个文件"的处境。安装器只负责把当前的核心 + 入口模板渲染到目标仓库，落地的内容可追溯、可卸载，但**它本身不持有任何业务规则**。

后续章节是这套思路的具体落地：第 1 节列出当前已经接入的工具入口，第 2 节给出共享占位符，第 3 节是适配层必须遵守的工程纪律，第 4 节划清不在本目录管辖范围的事项。

## 1. 模板清单

| 工具                     | 模板                                                                             | 落地位置（使用方仓库）                                                          |
| ------------------------ | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Claude Code              | [`claude-code/agent.skeleton.md`](./claude-code/agent.skeleton.md)               | `.claude/agents/<name>.md`                                                      |
| GitHub Copilot           | [`copilot/`](./copilot/README.md)（指令 + Custom Agent 套件）                    | `.github/copilot-instructions.md` / `.github/instructions/` / `.github/agents/` |
| OpenAI Codex / AGENTS.md | [`codex/agents.md.snippet`](./codex/agents.md.snippet)                           | 在仓库 `AGENTS.md` 末尾追加                                                     |
| 自研 Runtime             | [`generic/runtime-config.yaml.template`](./generic/runtime-config.yaml.template) | 由 Runtime 项目自管理                                                           |

> Copilot 一栏指向子目录而非单个文件——它包含一份顶层指令（`copilot-instructions.template.md`）、3 份切片指令（`instructions/`）、3 份专用 Custom Agent（`custom-agents/`），以及一份通用 Custom Agent 骨架 `custom-agent.skeleton.md`（可派生其他 6 个 Agent）。详细文件清单与复制步骤见 [copilot/README.md](./copilot/README.md)。

## 2. 通用替换占位符

所有模板中以下占位符在落地时替换：

| 占位符                          | 含义                                                                                                                                                |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `{{TEST_COMMAND}}`              | 项目级测试命令（如 `dotnet test`）                                                                                                                  |
| `{{LINT_COMMAND}}`              | 项目级风格检查命令                                                                                                                                  |
| `{{AGENT_NAME}}`                | Agent 名（如 `CodingExecutor`）                                                                                                                     |
| `{{AGENT_DIR}}`                 | Agent 目录的本地相对路径（如 `harness-engineering/agents/coding-executor`）                                                                         |
| `{{ONE_LINER}}`                 | Agent 一句话职责（来自 `AGENT.md` 「定位」章节首句）                                                                                                |
| `{{TOOL_LIST}}`                 | 工具白名单。抽象 ID 取自 [`_shared/tool-vocabulary.md`](../_shared/tool-vocabulary.md)，由各适配模板按目标工具的注册名做一次映射                    |
| `{{HARNESS_REPO_REF}}`          | 在采用方仓库中**引用 Harness 资源的本地路径**。默认安装走 vendor 模式，渲染为 `.harness-engineering`；`-NoVendor` 模式下渲染为远端 URL              |
| `{{HARNESS_REPO_REF_FROM_GITHUB}}` | 同上含义的**带回跳层级**版本。Custom Agent 文件落地在 `.github/agents/`，引用本地 vendor 时需要 `../.harness-engineering` 这种回跳路径才能正确点击 |

> 工具命名与抽象 vs 厂商：业务规则在 `agents/` 一份维护，但**工具白名单的命名空间不能强行抽象**——Copilot 要求 `tools` 字段写官方注册名（`codebase` / `search` / `changes` / `fetch` / `usages` 等），Claude Code 则用 `Read` / `Grep` / `Bash` 等大写动词。因此 Copilot Custom Agent 模板的 `tools` 字段直接写 Copilot 注册名，Claude Code 模板才使用 `{{TOOL_LIST}}` 占位符；两端的抽象映射只在 `_shared/tool-vocabulary.md` 一份维护。

## 3. 使用约定

- **不要**在模板里复制 `AGENT.md` / `prompt.md` 的正文。模板用相对路径 `@` 引用 / `include` 原文，避免双份维护。
- **不要**在模板里加项目业务约束。业务约束属于使用方仓库的 `AGENTS.md`，由工具自动按路径层级拼接。
- 模板需要随 `AGENT.md` 的输入输出契约同步更新。新增 / 调整 Agent 时，先改 `AGENT.md`，再回头检查这些模板。

## 4. 不在范围内

- 各 IDE 的扩展安装、登录配置：使用方自行处理
- CI / Webhook 编排：与 Agent 包装无关，由项目流水线管理
- 模型选择 / 计费：由使用方自管
