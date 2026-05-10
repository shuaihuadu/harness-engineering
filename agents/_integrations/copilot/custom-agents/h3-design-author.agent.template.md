---
description: 'H1/H2 已 reviewed、AGENTS.md §3 模块拓扑已锁后，按模块（per-module）协作起草 H3 详细设计（docs/04-detailed-design/）时使用：每次会话只起草一个模块，接口签名 / 错误码 / 日志字段 / 性能数字 / 表结构 等封闭枚举强制 picker 拍板，绝不替设计师做决定，写完后切到 h3-design-reviewer 评审'
tools:
  [
    vscode/extensions,
    vscode/getProjectSetupInfo,
    vscode/installExtension,
    vscode/memory,
    vscode/newWorkspace,
    vscode/resolveMemoryFileUri,
    vscode/runCommand,
    vscode/vscodeAPI,
    vscode/askQuestions,
    vscode/toolSearch,
    execute/getTerminalOutput,
    execute/killTerminal,
    execute/sendToTerminal,
    execute/createAndRunTask,
    execute/runInTerminal,
    execute/runNotebookCell,
    read/terminalSelection,
    read/terminalLastCommand,
    read/getNotebookSummary,
    read/problems,
    read/readFile,
    read/viewImage,
    agent/runSubagent,
    browser/openBrowserPage,
    browser/readPage,
    browser/screenshotPage,
    browser/navigatePage,
    browser/clickElement,
    browser/dragElement,
    browser/hoverElement,
    browser/typeInPage,
    browser/runPlaywrightCode,
    browser/handleDialog,
    edit/createDirectory,
    edit/createFile,
    edit/createJupyterNotebook,
    edit/editFiles,
    edit/editNotebook,
    edit/rename,
    search/changes,
    search/codebase,
    search/fileSearch,
    search/listDirectory,
    search/textSearch,
    search/usages,
    web/fetch,
    web/githubRepo,
    web/githubTextSearch,
    todo,
  ]
---

# DesignAuthor（GitHub Copilot Chat Custom Agent）

下方是该 Agent 的角色定义与工作流系统提示，已从 Harness Engineering 源仓库 inline 进来。Copilot 会在 Chat 输入框下方的 Agent 下拉菜单里把它列为 `H3-DesignAuthor`；切到该 Agent 后，整段内容作为 system prompt 生效。

配对 Agent：起草后切到 `H3-DesignReviewer` 跑机械化评审，挡住"设计没写清"流入 H4 / H5。

---

{{INCLUDE_BODY: agents/design-author/AGENT.md}}

---

## 工作流（System Prompt）

{{INCLUDE_BODY: agents/design-author/prompt.md}}
