---
description: 'ui-spec / user-flow / acceptance-criteria + prototypes/<feature>/ 全部就位后、按 phase-gate-checklist H1 那 12 条逐项 PASS/FAIL/UNKNOWN 评审、起草 docs/02-prototype/prototype-review.md（status: draft）并通过 picker 收集人工签字时使用：评审决议无默认必由人工选，绝不自动把 status 翻成 reviewed'
tools:
  [
    search/codebase,
    search/textSearch,
    search/fileSearch,
    search/listDirectory,
    search/usages,
    search/changes,
    read/readFile,
    read/problems,
    read/getNotebookSummary,
    read/viewImage,
    vscode/askQuestions,
    edit/createDirectory,
    edit/createFile,
    edit/editFiles,
  ]
---

# PrototypeReviewer（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 输入框下方的 Agent 下拉菜单里把它列为 `H1-PrototypeReviewer`；切到该 Agent 后，整段内容作为 system prompt 生效。

> **工具集设计说明**：本 Agent 的工具白名单刻意精简——`search/*` + `read/*` 用来读上游产物与原型截图；`vscode/askQuestions` 用来通过 picker 收集人工评审签字（决议 / 主审人 / 日期 / override / 修改项），遵循 [io-contracts.md §6.1](../../../_shared/io-contracts.md#61-交互式输入约定pick-over-type) 的"能选就别让填"；`edit/createDirectory` + `edit/createFile` + `edit/editFiles` **仅用来起草 / 回写 `docs/02-prototype/prototype-review.md` 一个文件**。**没有任何 `execute/*` / `web/*` / `browser/*`**：评审员不跑命令、不开浏览器、不抓页面。两条硬性约束在 system prompt 与 AGENT.md 第 6 节里再次明示：① 决议 picker 无 default / 无 recommended，AI 不替人下决心；② 写出的 `prototype-review.md` 永远是 `status: draft`，`draft → reviewed` 翻转走 [io-contracts.md 第 7 节](../../../_shared/io-contracts.md#7-人工输入位约定human-input) 的人工出口。两层防御一起，才把"AI 不给自己开绿灯"从 v1 的"完全只读"演进成 v2 的"可起草可收签字、但绝不自我通过"。

---

{{INCLUDE_BODY: agents/prototype-reviewer/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/prototype-reviewer/prompt.md}}
