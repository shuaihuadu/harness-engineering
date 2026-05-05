---
description: 'H1 已 approved 后起草 H2 架构说明、技术选型、风险分析与 ADR 时使用：每条选型必须留下"选择/为什么/替代方案/放弃理由/维护影响/成本性能安全交付影响"六字段，否则 H3/H5 将无法回溯决策证据'
tools: ['codebase', 'search', 'usages', 'fetch']
---

# ArchitectAdvisor（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 顶部下拉菜单里把它列为 `H2-ArchitectAdvisor`；切到该 Agent 后，整段内容作为 system prompt 生效。

---

{{INCLUDE_BODY: agents/architect-advisor/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/architect-advisor/prompt.md}}
