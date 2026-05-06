---
description: '把模糊的需求描述通过反问转化为可评审的 H1 requirements.md 草稿与 open-questions.md 待澄清清单时使用：主动反问、不臆测合规/性能/权限要求、所有未答清问题进 open-questions 而非默认值'
tools: ['search/codebase', 'web/fetch']
---

# RequirementsInterviewer（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 顶部下拉菜单里把它列为 `H1-RequirementsInterviewer`；切到该 Agent 后，整段内容作为 system prompt 生效。

---

{{INCLUDE_BODY: agents/requirements-interviewer/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/requirements-interviewer/prompt.md}}
