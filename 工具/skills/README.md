---
所属: 体系
必读: 按需
---

# 工具 Skills 登记

本目录存放协作体登记 skill 的**源码**（一份源码，各 Agent 通过链接指向使用）。skill 的加载机制、平台链接位置与不可用时的排查，见各平台 [skills接入](../../协作入口/Agent适配/DSH/skills接入.md) / [Codex](../../协作入口/Agent适配/Codex/skills接入.md) / [Hermes](../../协作入口/Agent适配/Hermes/skills接入.md)。安装/搭建/修复 skill 时按需读取[安装指引](./安装指引.md)。

## 已登记 skill

| Skill | 源码位置 | 类型 | 平台 |
|---|---|---|---|
| 优化流程线 | [体系优化/优化流程线/SKILL.md](./体系优化/优化流程线/SKILL.md) | 协作体自建 skill | DSH / Codex / Hermes |
| UA（Understand Anything） | [代码开发协作工具/Understand-Anything/](./代码开发协作工具/Understand-Anything/) | 外部 skill 仓库 | Codex / Hermes / DSH（复用） |
| UIUXProMax（ui-ux-pro-max） | [UIUXProMax/SKILL.md](./UIUXProMax/SKILL.md) | 外部 skill 仓库（设计情报库，Python 3.x） | DSH / Codex / Hermes |

## UA 场景表（Understand Anything，多子 skill 集中登记）

- 协作体 skill **不走平台自动注入**（各平台加载差异见对应 `skills接入.md`）；单一使用点的 skill（优化流程线、UIUXProMax 等）路径放在各自使用点文档，不在此表；仅 UA 因有 9 个子 skill、多个使用点，集中在此登记。
- 命中下表 UA 场景时，`read` 对应 `SKILL.md` 后按步骤执行；**同一窗口已读过的 SKILL.md 不重复读，直接用；未读过才 read**；不命中不读、不占上下文。

| 场景                         | 读取的 SKILL.md                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------ |
| 需要理解代码库架构/生成知识图谱           | `代码开发协作工具/Understand-Anything/understand-anything-plugin/skills/understand/SKILL.md` |
| 基于知识图谱问答                   | `.../skills/understand-chat/SKILL.md`                                                |
| 打开知识图谱可视化面板                | `.../skills/understand-dashboard/SKILL.md`                                           |
| 分析 git 改动与影响               | `.../skills/understand-diff/SKILL.md`                                                |
| 提取业务领域流程                   | `.../skills/understand-domain/SKILL.md`                                              |
| 深入解释文件/函数/模块               | `.../skills/understand-explain/SKILL.md`                                             |
| 分析 Figma 设计稿               | `.../skills/understand-figma/SKILL.md`                                               |
| 分析 wiki 知识库                | `.../skills/understand-knowledge/SKILL.md`                                           |
| 生成新人入职指南                   | `.../skills/understand-onboard/SKILL.md`                                             |

- UA 系列需要运行环境（Node ≥ 22、pnpm）时，按 `代码开发协作工具/Understand-Anything/README.md` 准备，按需安装。
- UIUXProMax 需要 Python 3.x（search.py 无外部依赖）；本机已装 Python 3.11.9。使用见 [UIUXProMax/README.md](./UIUXProMax/README.md)。

## 新增 skill 规则

- 新增 skill 前说明来源、位置、影响与可选方案，取得用户确认后登记。
- 源码统一放 `工具/skills/` 下；各平台通过链接指向源码，不复制多份。
