---
description: '需求与详细设计已 reviewed、需要起草或更新 H4 测试用例（docs/05-test-design/）时使用：从需求与设计反推 TC-NNN 测试矩阵与分组用例草稿，确保每条 REQ 至少有可机械判断的覆盖'
tools: ['codebase', 'search', 'usages', 'fetch']
---

# TestCaseAuthor（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 顶部下拉菜单里把它列为 `H4-TestCaseAuthor`；切到该 Agent 后，整段内容作为 system prompt 生效。

---

{{INCLUDE_BODY: agents/test-case-author/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/test-case-author/prompt.md}}
