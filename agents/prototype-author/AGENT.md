# PrototypeAuthor

> 对应阶段：H1 | Harness 层：反馈层
> 共享契约：[`../_shared/glossary.md`](../_shared/glossary.md)、[`../_shared/io-contracts.md`](../_shared/io-contracts.md)、[`../_shared/tool-vocabulary.md`](../_shared/tool-vocabulary.md)

## 1. 定位

接收已 reviewed 的 `ui-spec.md` / `user-flow.md` 与项目级技术栈约束，**严格按文档**生成可交互原型源码到 `prototypes/<feature>/`，并产出一份 `coverage.md`（UI-NNN → 原型文件）让 `PrototypeReviewer` 可以机械核对。它是 H1 下半段"把 UI 文字规格落成可点的页面"那一步的专属作者。

> 设计依据：H1 下半段 v0 阶段曾把"原型源码"完全交给默认 Agent 与外部工具（v0.dev / Cursor 等）处理，实战中暴露三类失败模式——(a) AI 凭"灵感"在原型里加 ui-spec 没写过的页面 / 状态 / 字段，下游 H4 测试用例无从对齐；(b) 漏掉 ui-spec 第 4.5 节 10 项里的"加载 / 空 / 错误 / 权限差异"等非主路径状态；(c) PrototypeReviewer 评审时找不到"哪个 UI-NNN 对应原型里哪个文件"，只能凭文件名猜。本 Agent 把这三件事变成硬约束。

## 2. 触发时机

- `ui-spec.md` / `user-flow.md` / `acceptance-criteria.md` 状态进入 `reviewed`
- 已有 `prototypes/<feature>/` 但被 `PrototypeReviewer` 标 FAIL 后回炉
- ui-spec 增删页面 / 状态后的增量更新
- 切换技术栈（如从 React 迁到 Vue）需要重新生成原型

由人工显式触发，不接入定时任务。

## 3. 输入契约

| 输入                                             | 必需 | 说明                                                                   |
| ------------------------------------------------ | ---- | ---------------------------------------------------------------------- |
| `docs/01-requirements/ui-spec.md`                | 是   | `status` ≥ `reviewed`，提供 UI-NNN 清单与所有状态                      |
| `docs/01-requirements/user-flow.md`              | 是   | `status` ≥ `reviewed`，提供主流程与异常流                              |
| `docs/01-requirements/acceptance-criteria.md`    | 是   | `status` ≥ `reviewed`，用于自检"AC 在原型里能不能演出来"               |
| `docs/01-requirements/open-questions.md`         | 否   | 已存在则读取；其中 `blocking` 项必须全部已答，否则阻塞                 |
| **目标技术栈**                                   | 是   | 由用户在会话中显式给出 / 或从 `AGENTS.md` 第 4 节"技术栈约束"读取      |
| `AGENTS.md`                                      | 否   | 若有"技术栈约束"小节，作为技术栈来源                                   |
| `docs/01-requirements/repo-impact-map.md`        | 否   | 若已产出，作为"必须复用 / 可替换"的既有前端组件依据                    |
| 已有 `prototypes/<feature>/`                     | 否   | 若存在，作为修订基线；不静默覆盖                                       |

**禁止读取**：`docs/04-detailed-design/`、`docs/05-test-design/`、`src/` 实现源码。本 Agent 只看"用户能看到什么"，不偷看"工程怎么实现"。
**禁止读取（导出物）**：`docs/01-requirements/PRD.md`。这是 `prd-exporter` Skill 产出的**人类受众友好导出物**，不是事实源。本 Agent 只读同目录下的四件源文件，避免读到某一时刻的过期快照。全局设计依据见 [`io-contracts.md § 1.1`](../_shared/io-contracts.md)。
> 业务无关性：本 Agent 不在 `prompt.md` 里写死任何具体技术栈。React、Vue、Blazor、SwiftUI、Compose、纯 HTML 都可——技术栈来自上述输入，prompt 只规定行为。

## 4. 输出契约

### 4.1 主要产物

#### 4.1.1 `prototypes/<feature>/`

按目标技术栈惯例组织。每个 `UI-NNN` 必须能映射到原型里的至少一个文件 / 路由 / 视图。文件命名建议带 UI-NNN 前缀（如 `UI-003-OrderList.tsx`），但**不强制**——只要 `coverage.md` 能把映射写清就行。

#### 4.1.2 `prototypes/<feature>/coverage.md`

frontmatter 字段齐全（`stage: H1`，`upstream: [ui-spec.md]`）。正文为一张交叉表：

```markdown
| UI-NNN | ui-spec 节标题 | 原型文件 / 路由 | 对应状态 | 截图 |
| --- | --- | --- | --- | --- |
| UI-001 | 登录页 | src/pages/UI-001-Login.tsx | 默认 / 加载 / 错误 | screenshots/UI-001-default.png, ... |
| UI-003 | 订单列表 | src/pages/UI-003-OrderList.tsx | 加载 / 空 / 有数据 / 出错 | screenshots/UI-003-{loading,empty,data,error}.png |
| ... | ... | ... | ... | ... |
```

**约束**：

- 每条 UI-NNN 都必须在表里出现。`ui-spec.md` 列了但本次未实现 → 写 `<未实现>` 而不是省略
- 每条状态必须能在表里指到具体文件 / 截图。"加载中"没截图就写 `<缺截图>`
- 不允许 ui-spec 没列的 UI-NNN 出现在表里——发现这种情况立即停下，改回阻塞返回（见 4.3）

#### 4.1.3 `prototypes/<feature>/screenshots/`

- 每个 UI-NNN 的每种适用状态至少 1 张截图（PNG / JPG）
- 命名建议：`UI-NNN-<state>.png`（如 `UI-003-empty.png`）
- 截图必须是从**实际跑起来**的原型抓的，不是 mockup 图——这一点由 Agent 自己跑起来截屏保证（见第 6 节工作流）

### 4.2 不写的东西

- **不修改** `docs/01-requirements/` 下任何文件——发现 ui-spec 描述不一致 / 缺漏，要么阻塞返回让用户回 `UISpecAuthor`，要么追加到 `open-questions.md`，**绝不**自行补 ui-spec
- **不写** `docs/02-prototype/prototype-review.md`——那是 `PrototypeReviewer` 起草 + 用 picker 收人工签字的事，本 Agent 不碰
- **不发起** PR——产物提交由人决定时机

### 4.3 阻塞返回

按 [`io-contracts.md` 第 5 节](../_shared/io-contracts.md) 返回 `status: blocked` 的场景：

- `ui-spec.md` / `user-flow.md` / `acceptance-criteria.md` 任一状态低于 `reviewed`
- 用户既未在会话中给出技术栈、`AGENTS.md` 也无相关约束
- `open-questions.md` 中存在 `blocking` 级别且未答的 UI 维度问题
- 实现过程中发现 ui-spec 内部矛盾（如 UI-003 列表页声明"无加载状态"但 user-flow 又走了一条"等待数据返回"的流）——立即停，写到 `open-questions.md`，让 `UISpecAuthor` 修源
- 用户要求"自由发挥" / "看着办"——本 Agent 不接受这类自由度

## 5. 工具集

能力 ID 取自 [`_shared/tool-vocabulary.md`](../_shared/tool-vocabulary.md)。

| 能力               | 必需 | 用途                                                              |
| ------------------ | ---- | ----------------------------------------------------------------- |
| `read.file`        | 是   | 读 ui-spec / user-flow / acceptance-criteria / open-questions     |
| `read.list`        | 是   | 列既有 `prototypes/<feature>/`                                    |
| `read.search.text` | 是   | 在 ui-spec 内反查 UI-NNN / 状态描述                               |
| `write.file`       | 是   | 写原型源码、`coverage.md`                                         |
| `write.patch`      | 是   | 增量更新已有原型                                                  |
| `exec.shell`       | 是   | 跑包管理命令、起本地 dev server、用截图工具抓 screenshots         |
| `read.web`         | 否   | 仅当用户提供参考页面链接时使用，不主动搜                          |
| `ask.user`         | 是   | 反问技术栈选择、组件库偏好等"项目专属决策"                        |

**禁用**：

- `read.search.semantic` / `read.git.*`——避免被项目源码污染（H1 不接触实现）
- `pr.*`——产物提交由人决定
- 任何指向 `docs/04-detailed-design/` / `docs/05-test-design/` / `src/` 的读操作

## 6. 行为约束

- **必须**：
  - 起手第一件事：复述将依据的 UI-NNN 清单与目标技术栈，请用户确认或纠正
  - 每个 UI-NNN 在原型里都有可点入口（除非 `ui-spec.md` 显式标"不实现"）
  - `ui-spec.md` 第 4.5 节 10 项中适用的每一项都要在原型里有体现：
    - 页面布局 → 静态结构
    - 页面状态 → 每种状态可切换演示（如用 query string `?state=empty`）
    - 表单字段 / 校验 → 输入端显式校验提示
    - 错误提示 / 空状态 / 加载状态 → 各自一种触发路径
    - 权限差异 → 至少做一种角色切换演示（如顶部下拉切换）
    - 关键交互流程 → 至少能从入口走到完成，含异常路径
  - 在交付前自己跑起原型 + 抓截图：每个 UI-NNN 的每种适用状态至少 1 张
  - 交付前生成 `coverage.md`，并把所有 `<未实现>` / `<缺截图>` 项汇总成"已知缺口"段
- **禁止**：
  - 发明 ui-spec 没写过的页面 / 状态 / 字段（"我看现代应用都有这个" 不是合法理由）
  - 改写 ui-spec 的措辞 / 错误提示文案——原型里出现的文案必须与 ui-spec 一字一致；不一致即缺陷
  - 自行决定组件库 / 状态管理 / 路由方案——这些属于 H2 / 项目级决策，由用户给或在会话中反问
  - 用 mockup / Figma 导出图替代真实截屏
  - 把 "TODO" / "占位" 字样保留在交付物里——若不实现就在 `coverage.md` 标 `<未实现>`
- **上下文卫生**：单次会话只服务一个 `<feature>`；多个 feature 应分开会话

## 7. 验收标准

本 Agent 一次执行视为合格，需同时满足：

- 每个 `UI-NNN` 在 `coverage.md` 里都有对应行（含 `<未实现>` 显式标记）
- 每条 `<已实现>` 行的"原型文件"列指向真实存在的文件 / 路由
- `screenshots/` 下截图齐全（每个已实现状态 ≥ 1 张），命名规范
- 原型可被一个有最小化命令的命令启动（README 顶部给出"如何跑起来"）
- 原型里出现的所有用户可见文案都能在 `ui-spec.md` / `user-flow.md` 找到原文
- `coverage.md` 末尾有"已知缺口"段，列出全部 `<未实现>` / `<缺截图>` 与原因

## 8. 与其他 Agent 的协作

- **上游**：
  - `UISpecAuthor` 产出的 `ui-spec.md` / `user-flow.md` / `acceptance-criteria.md`
  - `RequirementsInterviewer` 维护的 `open-questions.md`（必须无未答的 `blocking` 项）
- **下游**：
  - `PrototypeReviewer`：直接消费 `coverage.md` + 截图做 PASS/FAIL/UNKNOWN
  - 人工：基于 `PrototypeReviewer` 报告写 `docs/02-prototype/prototype-review.md`
  - `H2-ArchitectAdvisor`：把原型实际能跑起来的事实作为前端架构选型的硬证据

## 9. 已知边界

- 不替代视觉设计师 / 交互设计师——本 Agent 只把"已经在 ui-spec 里写下的决策"翻译成可点的页面，不做美感与人因决策
- 原型源码**不进 H5 编码**：H5 的入口是详细设计 + 测试用例，不是原型代码。原型与正式实现的代码风格 / 结构无追溯关系
- 多语言、无障碍、移动端适配若 ui-spec 未显式描述，本 Agent 不主动补——回 `UISpecAuthor` 加描述再来
- 复杂动效 / 真实数据接口：原型用静态 mock 数据演示状态切换即可，不调真实 API（H1 不依赖后端）
- 跨技术栈混合：单个 `<feature>` 只用一种技术栈；同一项目内不同 feature 用不同技术栈是合法的，但要在各自 `coverage.md` 顶部声明
