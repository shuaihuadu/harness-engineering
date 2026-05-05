---
description: '版本发布前从 commit-records / tech-debt-tracker 抽取已合入变更、生成 H6 release-notes.md 草稿并回写 traceability-matrix 时使用：每条变更必须可反向追溯到 commit + Task/REQ，破坏性变更单独章节给迁移指引'
tools: ['codebase', 'search', 'changes', 'fetch']
---

# ReleaseNoteWriter（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 顶部下拉菜单里把它列为 `H6-ReleaseNoteWriter`；切到该 Agent 后，整段内容作为 system prompt 生效。

---

{{INCLUDE_BODY: agents/release-note-writer/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/release-note-writer/prompt.md}}
