---
name: prd-exporter
description: 把 H1 已评审的四件产物（requirements.md / ui-spec.md / user-flow.md / acceptance-criteria.md）合并导出为单文件 PRD。当用户说"给我一份 PRD"、"客户/老板要看产品需求文档"、"把需求合并成对外版本"、"H1 输出能不能给非工程同学看"时主动调用。本 Skill 是**只读导出**：单一事实源仍是 H1 那四件产物，导出的 PRD 不能被独立编辑——发现 PRD 与四件产物有偏离，必须改源、再重导，绝不允许把 PRD 当作新事实源。
when_to_use: |
  - H1 四件产物已 reviewed，需要给客户 / 老板 / 跨部门同事一份合并文档
  - 项目立项 / 评审会前，需要把分散的需求与 UI 信息凝练成一份可读 PRD
  - 已有 PRD 文档落后于 H1 源文件，需要重新导出对齐
when_not_to_use: |
  - H1 还在 draft 阶段——导出会把未定稿信息扩散出去
  - 用户想"修改 PRD"——直接改 PRD 等于背叛单一事实源原则；改源文件再重导
  - 用户问的是"H1 怎么写"——那是 RequirementsInterviewer / UISpecAuthor 的事
---

# Skill: PRD 导出器（PRD Exporter）

## 1. 目的与原理

H1 的产物在 Harness Engineering 里被刻意拆成四件，理由很硬：

- `requirements.md` 是业务侧事实（背景、用户、范围、不做）
- `ui-spec.md` 是 UI 事实（页面、状态、字段、权限差异）
- `user-flow.md` 是流程事实（主流程、异常流）
- `acceptance-criteria.md` 是验收事实（可机械判定的成功条件）

四件分开维护，各自的评审与变更影响面更可控；但对**非工程读者**（客户、销售、新加入的产品同学）来说，分开读会丢上下文。所以需要一个**只读的合并视图** = PRD。

> **核心纪律**：PRD 是**导出视图**，不是**新事实源**。任何对 PRD 的编辑都必须回流到对应源文件，再重新导出。本 Skill 在生成的 PRD 顶部强制写一条提示："本文件由 prd-exporter 从 H1 源文件生成，请勿直接编辑。"

为什么不做成 Agent：参见 [`agents/README.md` 第 7.3 节](../../README.md#73-何时新增-agent)三问测试——H1 现有 4 个 Agent 已经把 PRD 的全部章节都覆盖了，再加一个 PM Agent 就是重复维护。

## 2. 输入

必需（必须全部存在且 frontmatter `status` ≥ `reviewed`）：

- `docs/01-requirements/requirements.md`
- `docs/01-requirements/ui-spec.md`
- `docs/01-requirements/user-flow.md`
- `docs/01-requirements/acceptance-criteria.md`

可选：

- `docs/02-prototype/prototype-review.md`（如已产出，作为 PRD 中"原型确认"小节的引用）
- `prototypes/<feature>/screenshots/`（截图相对路径，PRD 内嵌图片引用）

**禁止输入**：`docs/03-architecture/` 及之后的产物——PRD 是产品视角，不能掺架构与实现。

## 3. 步骤

### 3.1 校验四件源文件状态

读各文件 frontmatter，逐项核对：

- `status: reviewed` 或 `approved`（为 `draft` 则停下，提醒"H1 未定稿不能导 PRD"）
- `reviewers:` 字段非空
- 文件之间的版本号 / 更新日期是否一致（不一致时给警告但不阻塞，让用户决定是否继续）

任一项不通过 → 停下并报告，不要带病导出。

### 3.2 抽章节、按 PRD 模板拼接

PRD 模板（节序固定）：

```markdown
# <项目名> · 产品需求文档（PRD）

> 本文件由 prd-exporter 从 H1 源文件自动生成于 <YYYY-MM-DD HH:MM>。
> 单一事实源：`docs/01-requirements/{requirements,ui-spec,user-flow,acceptance-criteria}.md`
> 请勿直接编辑本文件——任何修改都应回到源文件再重新导出。

| 字段 | 内容 |
| --- | --- |
| 版本 | <从最新源文件 frontmatter 取，或显式写 `consolidated`> |
| 状态 | <四件中最低的 status> |
| 评审人 | <四件 reviewers 并集> |
| 来源快照 | <git commit sha> |

---

## 1. 项目背景与目标

<来自 requirements.md「项目背景」+「目标」>

## 2. 目标用户与角色

<来自 requirements.md「目标用户」+「用户角色」>

## 3. 核心场景

<来自 requirements.md「核心场景」+ user-flow.md 的主流程图（用文字描述或 Mermaid）>

## 4. 功能范围

### 4.1 做什么
<来自 requirements.md「功能范围」>

### 4.2 不做什么
<来自 requirements.md「不做什么」——这一节必须显式保留，不能省>

## 5. 非功能需求

<来自 requirements.md「非功能需求」+「权限边界」+「数据边界」>

## 6. 用户界面

### 6.1 页面清单
<来自 ui-spec.md「页面清单」>

### 6.2 关键页面布局与状态
<来自 ui-spec.md「页面布局」+「页面状态」+「空状态」+「加载状态」>

### 6.3 表单字段与操作
<来自 ui-spec.md「表单字段」+「操作按钮」>

### 6.4 错误与权限差异
<来自 ui-spec.md「错误提示」+「权限差异」>

## 7. 用户流程

<来自 user-flow.md，主流程 + 异常流分小节>

## 8. 验收标准

<来自 acceptance-criteria.md，逐条编号保留>

## 9. 异常场景

<来自 requirements.md「异常场景」>

## 10. 原型确认（可选）

<如有 docs/02-prototype/prototype-review.md，引用其结论 + 截图相对路径>

---

## 附录 A. 源文件追溯

| PRD 章节 | 源文件 | 章节锚点 |
| --- | --- | --- |
| 1. 项目背景 | requirements.md | #项目背景 |
| 2. 目标用户 | requirements.md | #目标用户 |
| ... | ... | ... |
```

### 3.3 字段不全时的处理

源文件里可能某些章节是空的（例如 `requirements.md` 没写「异常场景」）。处理规则：

- **不要静默跳过**：在 PRD 对应章节写 `> 源文件未提供本节内容（来源：<file>#<section>）`
- 同时把该缺口列入产物末尾的"导出警告清单"——让导出方有意识地决定是否回去补 H1
- **不要凭空生成**：H1 没写过的内容不能由 PRD 凭印象补，违反单一事实源原则

### 3.4 落盘建议

落到 `docs/01-requirements/PRD.md`（与四件源文件同目录，便于评审者一起看到）。

> 注意：PRD.md 的 `status` 永远是 `generated`，不是 `draft/reviewed/approved`。它的"评审"通过四件源文件的评审间接达成。Phase-gate-runner 检查 H1 时，**不应**把 PRD.md 计入清单——它只是导出物。

### 3.5 增量重导

如果 PRD.md 已存在：

- 比对四件源文件的 commit sha vs PRD 顶部记录的快照 sha
- 一致：报告"无需重导"
- 不一致：列出差异源文件 + 受影响的 PRD 章节，请用户确认是否覆盖

不要静默覆盖人工编辑过的 PRD——如果发现 PRD 中存在源文件没有的内容，优先报告"PRD 已被人工编辑，先把这些内容回流到源文件再重导"。

## 4. 失败模式与回退

- **源文件 status=draft**：拒绝导出。理由：PRD 用于对外，draft 内容外泄会让"未评审就被消费"反模式落地。
- **四件文件版本号不一致**：给警告，建议先用 `phase-gate-runner` 跑一次 H1 门禁，对齐版本后再导。
- **被要求"删掉某节"或"加一节"**：拒绝。让用户改源文件 / `requirements.md` 加章节后重导，或在仓库外部维护"客户定制版"——但客户定制版不进 docs/。
- **被要求生成英文版 / 多语言**：本 Skill v1 只导出与源文件同语言的 PRD。多语言由专门的翻译流程处理。

## 5. 示例

**输入**：

> H1 都过审了，给我一份 PRD 给客户看。

**操作**：

1. 读 `docs/01-requirements/{requirements,ui-spec,user-flow,acceptance-criteria}.md`，确认 4 个文件 `status: approved`
2. 取 `git log -1 --format=%h docs/01-requirements/` 作为来源快照
3. 按 3.2 模板拼接，发现 `requirements.md` 没写「异常场景」 → 在 PRD 第 9 节写"源文件未提供本节内容"，并加入导出警告

**输出（节选）**：

```markdown
# Inkwell · 产品需求文档（PRD）

> 本文件由 prd-exporter 从 H1 源文件自动生成于 2026-05-08 14:30。
> 单一事实源：`docs/01-requirements/{requirements,ui-spec,user-flow,acceptance-criteria}.md`
> 请勿直接编辑本文件——任何修改都应回到源文件再重新导出。

| 字段 | 内容 |
| --- | --- |
| 版本 | v0.3 |
| 状态 | approved |
| 评审人 | @alice, @bob |
| 来源快照 | a1b2c3d |

...

## 9. 异常场景

> 源文件未提供本节内容（来源：requirements.md#异常场景）

---

## 导出警告

- requirements.md「异常场景」为空。建议回到 H1 由 RequirementsInterviewer 补全后重导。
```

## 6. 与其它 Skill / Agent 的边界

- 想**写新需求**：用 `RequirementsInterviewer` Agent，不是本 Skill。
- 想**评 PRD 内容好不好**：本 Skill 不评内容；评 H1 内容用 `PrototypeReviewer` Agent + `phase-gate-runner` Skill。
- 想**生成给开发看的合并文档**：开发应该直接读四件源文件 + 详细设计 + 测试用例，不要从 PRD 读取。PRD 是对外视图，不是工程入口。
- 想**做版本对比 / changelog**：用 git diff，本 Skill 不做版本管理。
