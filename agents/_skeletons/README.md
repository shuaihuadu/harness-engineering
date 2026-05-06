# `_skeletons/` · 新增 Agent 时的起头骨架

这个目录是 [Harness Engineering](../../README.md) 的**未来扩展工具箱**——**当前已经建好的 Agent 都不依赖它**。它的存在只为一件事：当你想给规范加**新的 Agent**（H7?、新阶段、新工具集成）时，这里有现成的"母版"可以复制。

> **关键定位**：
>
> - 不进采用方仓库（`sync-engine` 显式跳过 `*.skeleton.md`）
> - 不进 vendor 目录（卸载脚本不会处理它们）
> - 不被任何运行时 / 安装流程读取
> - 只在"作者新增一个 Agent"这一动作里被人手 copy 一次

如果你只是用现有 Agent，可以彻底忽略这个目录。

## 1. 目录里有什么

| 文件                                                                     | 干啥用                                                                       |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| [`AGENT.skeleton.md`](./AGENT.skeleton.md)                               | 新 Agent 的 `AGENT.md` 起点：定位 / 触发 / 输入 / 输出 / 落地清单等 9 节骨架 |
| [`prompt.skeleton.md`](./prompt.skeleton.md)                             | 新 Agent 的 `prompt.md`（系统提示）起点                                      |
| [`claude-code-wrapper.skeleton.md`](./claude-code-wrapper.skeleton.md)   | 把现有 Agent 接入 Claude Code 工具时复制改的包装层                           |
| [`copilot-custom-agent.skeleton.md`](./copilot-custom-agent.skeleton.md) | 给 Copilot Custom Agent 起头（与 `_integrations/copilot/` 体系对齐）         |

每个文件里的 `<占位>` 是**给作者填的**——不是 `{{KEY}}` 那种由 sync-engine 自动替换的占位。

## 2. 后缀对比（避免与 `*.template.md` 混淆）

| 后缀            | 谁来填空                                        | 何时被消费           | 是否进采用方仓库            |
| --------------- | ----------------------------------------------- | -------------------- | --------------------------- |
| `*.template.md` | sync-engine 自动替换 `{{KEY}}` / `{{INCLUDE:}}` | 每次 install         | 是（渲染后落到 `.github/`） |
| `*.skeleton.md` | **作者** copy 后人手填 `<占位>`                 | 仅"新增 Agent"这一次 | 否（仅在源仓库存在）        |
| 普通 `*.md`     | 无（照原样字节拷贝）                            | 每次 install         | 是                          |

## 3. 工作流（新增一个 Agent 时怎么用）

假设你要加 `h7-incident-responder`：

```bash
# 1. 起新 Agent 目录
mkdir agents/h7-incident-responder

# 2. 用 skeleton 起头
cp agents/_skeletons/AGENT.skeleton.md   agents/h7-incident-responder/AGENT.md
cp agents/_skeletons/prompt.skeleton.md  agents/h7-incident-responder/prompt.md

# 3. 把 <占位> 全填掉，写完整逻辑（最关键的工作量在这里）

# 4. 给它做一份 Copilot Custom Agent 包装
#    — 直接编辑 _integrations/copilot/custom-agents/h7-incident-responder.agent.template.md
#    — 里面用 {{INCLUDE_BODY: agents/h7-incident-responder/AGENT.md}} 自动拼装
#    — 这一步用的是 .template.md（机器渲染），不是 .skeleton.md（人手抄写）
#    — 如果不知道 .agent.template.md 怎么写，参考已有 9 个 h*.agent.template.md 中任一份

# 5. install.ps1 重新跑，新 Agent 自动出现在采用方的 .github/agents/ 下
```

## 4. 要不要因为"当前没人用"就删掉它们？

**不删**。理由：

1. 总尺寸 ~5KB，零维护成本（不参与 lint / 不进 CI / 不影响安装）
2. 当未来真要加 Agent 时，少了它就得现去翻 9 个 `h*` Agent 反推"AGENT.md 应该长啥样"——比直接 copy 一份骨架慢一个数量级
3. 它们携带了关键的"格式契约"——比如对 [`io-contracts.md`](../_shared/io-contracts.md) / [`glossary.md`](../_shared/glossary.md) / [`tool-vocabulary.md`](../_shared/tool-vocabulary.md) 的引用约定

如果你在评审中怀疑它们腐化了（被现有 Agent 的实际写法甩开），处理方式是**回头同步骨架**而非删除——因为这恰好揭示了"H1-H6 沉淀下来的最佳实践还没回写到骨架里"。

## 5. 何时该改 skeleton

只有以下场景需要改：

- 给"AGENT.md 应该有几节"加 / 删 / 改一节（罕见，会同时影响 `_shared/io-contracts.md`）                
- 给 `tool-vocabulary.md` 加新工具，需要在 wrapper skeleton 里登记
- 接入新工具集成（如 Cursor / Cline），新增一份 `<vendor>-wrapper.skeleton.md`

不要因为"某个具体 Agent 这样写更顺"就改 skeleton——那属于个例，不是骨架。
