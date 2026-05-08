---
title: Harness Engineering 通用 Skills
---

# 通用 Skills

本目录提供一组**可被任意 Agent 或默认会话复用的操作型 Skill**。它们与 [`../`](../) 下的 Agent 不同：

- **Agent**：一个独立角色，会接管整个会话，按自己的工作流推进任务（比如 `design-reviewer` 会按固定步骤评审 H3 设计）。
- **Skill**：一个**可重入的 SOP**，描述"遇到 X 任务时按这个步骤来"。模型平时不加载，命中触发条件才查阅。Agent 内部也可以引用 Skill，避免在多个 Agent 的 prompt 里重复同一段操作流程。

边界口诀：**Agent 是「我现在是谁」，Skill 是「我现在要做哪件事的标准做法」。**

| 维度       | Agent                                | Skill                                          |
| ---------- | ------------------------------------ | ---------------------------------------------- |
| 触发方式   | 用户在 IDE 下拉里**显式切换**         | 模型在会话中按 `description` **语义匹配命中**   |
| 生命周期   | 接管整个会话                          | 命中后只读完成单次任务，不改变会话身份         |
| 输入输出   | 完整文档落地（`docs/...`）           | 函数式：明确的入参 + 明确的产物                 |
| 复用粒度   | 一个阶段一个 Agent                    | 跨 Agent / 跨阶段的元动作                      |

> 设计目的：把规范里的元动作（追溯、写任务卡、写提交信息、阶段门禁核对）从各 Agent 的 prompt 里抽出来，做成单一事实来源。Agent 的 prompt 因此可以更短，也更不容易随 Skill 变更而漂移。

## 1. 当前 Skill 清单

通用类（跨阶段元动作）：

| 名称                                                           | 解决的问题                                              | 主要消费者                                          |
| -------------------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------- |
| [traceability-linker](./traceability-linker/SKILL.md)          | 校验并补全 `REQ ↔ HD ↔ TC ↔ Task ↔ Commit` 追溯链       | DesignReviewer / CommitAuditor / RepoImpactMapper   |
| [ai-task-brief-writer](./ai-task-brief-writer/SKILL.md)        | 把口头需求/Issue 转成符合 `templates/ai-task-brief.md` 的 H5 任务卡 | 默认会话 / CodingExecutor 启动前        |
| [commit-message-formatter](./commit-message-formatter/SKILL.md) | 按 io-contracts.md 第 4 节的六字段模板生成或校验提交信息   | 任意阶段                                            |
| [phase-gate-runner](./phase-gate-runner/SKILL.md)              | 按 `templates/phase-gate-checklist.md` 机械核对阶段门禁 | 阶段切换时                                          |

阶段证据评审类（"清单项的证据是否在文件里"，与 phase-gate-runner 形成两层）：

| 名称                                                            | 解决的问题                                              | 主要消费者                                       |
| --------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------ |
| [architecture-reviewer](./architecture-reviewer/SKILL.md)       | H2 选型六字段 + 一致性 + 风险缓解的证据级核查           | H2→H3 切换前；ArchitectAdvisor 自审后的二次复核 |
| [test-plan-reviewer](./test-plan-reviewer/SKILL.md)             | H4 REQ × TC 矩阵 + TC 字段齐全 + 文件级覆盖证据核查     | H4→H5 切换前；TestCaseAuthor 自审后的二次复核   |
| [release-reviewer](./release-reviewer/SKILL.md)                 | H6 commit ↔ release-notes 双向对账 + 破坏性变更迁移指引 | 打 tag / 发包前；ReleaseNoteWriter 自审后的二次复核 |

商业 / 产品视图类（业务无关；不进追溯链）：

| 名称                                                | 解决的问题                                          | 主要消费者                          |
| --------------------------------------------------- | --------------------------------------------------- | ----------------------------------- |
| [effort-estimator](./effort-estimator/SKILL.md)     | HD/file-structure → T-shirt 工程复杂度矩阵（不出工时、不出钱） | PM/PJM 报价前；H3 评审末尾拆条决策 |
| [prd-exporter](./prd-exporter/SKILL.md)             | H1 四件产物合并导出为只读 PRD 单文件                | 对客户 / 老板 / 跨部门同事呈现需求时 |

## 2. Skill 的结构约定

每个 Skill 都遵循以下骨架（沿用 Anthropic Skills 生态的写法，便于跨工具复用）：

```text
<skill-name>/
  SKILL.md          # 必需。YAML frontmatter + Markdown 正文
  references/       # 可选。大块只读资料，按需读
  scripts/          # 可选。可执行脚本，提交确定性子任务
  assets/           # 可选。模板、样例文件
```

`SKILL.md` frontmatter 至少包含：

```yaml
---
name: <skill 名，与目录同名>
description: <一句话触发语义，包含关键词；写得"主动"一些，倾向多触发而非少触发>
when_to_use: |
  <2-3 行具体场景>
when_not_to_use: |
  <显式排除，避免误触发>
---
```

正文以**命令式**为主，重在解释"为什么这么做"，而不是堆 `MUST` / `NEVER`——LLM 在理解动机后能更稳定地泛化。

## 3. 触发与加载

- **GitHub Copilot 项目技能**：安装脚本会把每个 Skill 渲染到采用方仓库的 `.github/skills/<name>/SKILL.md`。Copilot CLI 与 VS Code Copilot 会自动扫描该目录，按 frontmatter 里的 `description` 做语义匹配，命中后才把整份 `SKILL.md` 注入上下文；用户也可用 `/skill-name` 显式调用。详见[官方文档](https://docs.github.com/zh/copilot/how-tos/copilot-cli/customize-copilot/add-skills)。
- **Claude Code / 自研 Runtime**：直接把 `agents/_skills/` 或 vendor 后的 `.he/agents/_skills/` 加入 Agent runtime 的 skill 索引即可。
- **触发逻辑**：模型基于 `description` 做语义匹配，自动决定是否阅读完整 `SKILL.md`。description 写得越精准、越接近真实用户语言，命中率越高。

## 4. 新增 Skill 的判断标准

加之前先问自己：

1. 是否会在 ≥2 个 Agent / 阶段中复用？只有一个调用方时，写在那个 Agent 的 prompt 里就够了。
2. 是否是**操作流程**（how-to），而不是规则（rule）或角色（role）？规则归 `instructions/`，角色归 `agents/<name>/`。
3. 是否业务无关？涉及具体技术栈的 SOP 应该放回消费仓库，而不是污染规范骨架。

三条都点头再考虑动手。规模克制是 Harness Engineering 的反过量原则之一（见 README 第 6.4 节）。

## 5. 不要把 Skill 当 Memory 用

各家 AI 工具都提供"记忆层"（CLAUDE.md / Copilot 用户 Memory / Cursor 个人 Rules 等）。Skill 与 Memory 的边界要划清：

- **Skill** 是**仓库里的可复用 SOP**，跟着仓库走、能被 diff 和 review、对所有协作者一致生效
- **Memory** 是**单人偏好与一次性上下文**，跟着会话或个人账号走，团队看不到也对不齐

判断口径：**这件事一旦换个人接手就该照样生效吗？** 是 → 写成 Skill / Rule / Scripts；只对自己生效 → 留在 Memory。错题集与故障复盘特别要警惕：如果只在私人 Memory 里堆"上次踩过的坑"，下次换人或换会话就重新踩。重要反例必须晋升一层——能机械判定的进 Scripts，不能机械判定的进 Rule，并且都要有 commit 记录。详见 [`../../README.md` 第 6.6 节](../../README.md#66-团队真相落仓库个人偏好留-memory)。
