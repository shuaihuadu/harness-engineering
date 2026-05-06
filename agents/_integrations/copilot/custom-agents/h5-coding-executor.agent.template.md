---
description: '在 ai-task-brief.md 已被人工评审通过、需要 AI 严格按任务说明完成 H5 编码 + 自验证时使用：仅修改"允许修改的文件"，禁止扩大范围，每次修改后跑 Verify 命令，超范围或缺命令时返回阻塞而非自行降级'
tools: ['search/codebase', 'search', 'usages', 'editFiles', 'runCommands']
---

# CodingExecutor（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 顶部下拉菜单里把它列为 `H5-CodingExecutor`；切到该 Agent 后，整段内容作为 system prompt 生效。

---

{{INCLUDE_BODY: agents/coding-executor/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/coding-executor/prompt.md}}
