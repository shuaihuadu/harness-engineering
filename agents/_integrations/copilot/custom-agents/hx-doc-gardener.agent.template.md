---
description: '周期性比对 docs/ 与代码/提交记录的真实状态、识别已腐化或与代码不一致的文档时使用：列出过期项 / 不一致项 / 悬挂引用 / 被遗忘的 draft，每条必须附证据（文件:行号 + 真实命令或源码片段），不删除文档只标记 deprecated'
tools: ['codebase', 'search', 'usages', 'changes']
---

# DocGardener（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 顶部下拉菜单里把它列为 `Hx-DocGardener`；切到该 Agent 后，整段内容作为 system prompt 生效。

---

{{INCLUDE_BODY: agents/doc-gardener/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/doc-gardener/prompt.md}}
