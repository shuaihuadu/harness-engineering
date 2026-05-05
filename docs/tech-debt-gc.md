---
title: 熵与技术债务 GC
parent: ../README.md
---

# 熵与技术债务 GC

本文件是 Harness Engineering 规范的技术债务治理章节，从 [`../README.md`](../README.md) 抽出。原 README §10.1–§10.3 的内容在本文件中作为独立章节展开。

> 在 H6 交付后，AI 代码仓库会随时间产生"状态熵"，需要持续清理。该章实践经验来自 OpenAI Codex 团队在 *Harness engineering* 一文中提出的方案。

## 1. 黄金原则（Golden Principles）

团队应提炼出一组可机械化检查的"黄金原则"，描述项目期望代码库保持的形状：

- 优先使用共享工具包，避免手写重复逻辑
- 在边界始终使用类型验证（parse, don't validate），不凭猜测推送数据形状
- 结构化日志、命名约定、文件大小上限等"品味不变式（taste invariants）"需以 Lint 硬拦截
- 跨层依赖只能沿架构图预设方向，逾越者报错

这些原则需写进 `docs/` 下的权威文档（如 `quality-grade.md`）并同步编码为可执行检查。

> 与 [`../README.md` 第 6.5 节](../README.md#65-软约束的失败模式与处置阶梯) 软约束阶梯口径一致：能机械判定的原则一律下沉为 Scripts / Lint / CI；停在自然语言层的原则迟早会被解释性绕过。

## 2. 定期 GC 任务

建议在仓库中配置定期运行的后台 AI 任务，完成以下事项：

- 扫描代码库与黄金原则的偏离，开启重构 PR
- 扫描 `docs/` 下与代码实际行为不一致的过期文档（doc-gardening），开启修复 PR
- 更新 `docs/06-implementation/exec-plans/tech-debt-tracker.md` 中的未完成项
- 合并选项：质量评级 / quality grade 表可在项目初期仅补充到 `docs/04-detailed-design/` 或 `docs/07-release/` 中

文档治理这条线由 [`../agents/doc-gardener/AGENT.md`](../agents/doc-gardener/AGENT.md) 负责落地。

## 3. 使用原则

- **持续偿还 > 集中重构**：技术债务像高利息贷款，每日少量偿还远优于积压后被迫集中返工。
- **人的品味一次捕获，机器永久执行**：评审心得、重构经验、线上故障复盘，要么转化为 `AGENTS.md` / Skill 里的指导，要么转化为 Lint / Hooks / CI 检查。
- **允许小幅 PR 自动合并**：GC 产出的 PR 如果可以在一分钟内评审完毕，应设置成可自动合并。

## 4. 与其他章节的关系

- 团队真相 vs 个人 Memory 的边界：见 [`../README.md` 第 6.6 节](../README.md#66-团队真相落仓库个人偏好留-memory)
- 软约束 → 硬约束的下沉口径：见 [`../README.md` 第 6.5 节](../README.md#65-软约束的失败模式与处置阶梯)
- DocGardener 的产物落点与触发条件：见 [`../agents/doc-gardener/AGENT.md`](../agents/doc-gardener/AGENT.md)
