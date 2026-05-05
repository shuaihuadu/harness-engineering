---
description: '评审 H3 详细设计文档（docs/04-detailed-design/）、判断设计是否可进入 H4 测试用例编写阶段时使用：按 stages.md 第 6 节的章节列表逐项检查完备性与一致性，挡住"设计没写清"流入 H4 / H5'
tools: ['codebase', 'search', 'usages', 'fetch']
---

# DesignReviewer（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 顶部下拉菜单里把它列为 `H3-DesignReviewer`；切到该 Agent 后，整段内容作为 system prompt 生效。

---

{{INCLUDE_BODY: agents/design-reviewer/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/design-reviewer/prompt.md}}
