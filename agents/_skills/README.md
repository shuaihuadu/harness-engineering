---
title: Harness Engineering 通用 Skills
---

# 通用 Skills

本目录提供一组**可被任意 Agent 或默认会话复用的操作型 Skill**。它们与 [`../`](../) 下的 Agent 不同：

- **Agent**：一个独立角色，会接管整个会话，按自己的工作流推进任务（比如 `design-reviewer` 会按固定步骤评审 H3 设计）。
- **Skill**：一个**可重入的 SOP**，描述"遇到 X 任务时按这个步骤来"。模型平时不加载，命中触发条件才查阅。Agent 内部也可以引用 Skill，避免在多个 Agent 的 prompt 里重复同一段操作流程。

> 设计目的：把规范里的元动作（追溯、写任务卡、写提交信息、阶段门禁核对）从各 Agent 的 prompt 里抽出来，做成单一事实来源。Agent 的 prompt 因此可以更短，也更不容易随 Skill 变更而漂移。

## 1. 当前 Skill 清单

| 名称                                                           | 解决的问题                                              | 主要消费者                                          |
| -------------------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------- |
| [traceability-linker](./traceability-linker/SKILL.md)          | 校验并补全 `REQ ↔ HD ↔ TC ↔ Task ↔ Commit` 追溯链       | DesignReviewer / CommitAuditor / RepoImpactMapper   |
| [ai-task-brief-writer](./ai-task-brief-writer/SKILL.md)        | 把口头需求/Issue 转成符合 `templates/ai-task-brief.md` 的 H5 任务卡 | 默认会话 / CodingExecutor 启动前        |
| [commit-message-formatter](./commit-message-formatter/SKILL.md) | 按 io-contracts.md 第 4 节的六字段模板生成或校验提交信息   | 任意阶段                                            |
| [phase-gate-runner](./phase-gate-runner/SKILL.md)              | 按 `templates/phase-gate-checklist.md` 机械核对阶段门禁 | 阶段切换时                                          |

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

- **GitHub Copilot / VS Code**：Skill 文件随 vendor 落到消费仓库的 `.harness-engineering/agents/_skills/`，并由 `copilot-instructions.md` 中的引用列表暴露给模型。
- **Claude Code / 自研 Runtime**：直接把目录路径加入 Agent runtime 的 skill 索引即可。
- **触发逻辑**：模型基于 `description` 字段做语义匹配，自动决定是否阅读完整 `SKILL.md`。description 写得越精准、越接近真实用户语言，触发命中率越高。

## 4. 新增 Skill 的判断标准

加之前先问自己：

1. 是否会在 ≥2 个 Agent / 阶段中复用？只有一个调用方时，写在那个 Agent 的 prompt 里就够了。
2. 是否是**操作流程**（how-to），而不是规则（rule）或角色（role）？规则归 `instructions/`，角色归 `agents/<name>/`。
3. 是否业务无关？涉及具体技术栈的 SOP 应该放回消费仓库，而不是污染规范骨架。

三条都点头再考虑动手。规模克制是 Harness Engineering 的反过量原则之一（见 README 第 6.4 节）。
