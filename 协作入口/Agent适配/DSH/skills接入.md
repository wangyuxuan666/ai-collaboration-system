---
所属: 体系
必读: 按需
---

# DSH skills 接入

仅在当前需要使用的已登记 skill 缺失、断链或未发现时读取本文件；只处理该 skill。通用处理流程见[工具接入与故障处理 SOP](../README.md)，本文件只列 DSH 的 skill 加载机制；已登记 skill 清单见[工具/skills/README.md](../../../工具/skills/README.md)。

## 加载机制（按需读取）

- DSH 的技能自动注入已禁用（`tool-skill` 关闭），`available_skills` 目录和 `skill` 工具不存在。
- 协作体 skill 按需使用：按 skill 各自使用点文档指引 read 对应 `SKILL.md`（UA 场景见[UA 场景表](../../../工具/skills/README.md)，优化流程线见[维护方针 Skill 索引](../../AI协作体系维护/AI协作体系维护方针.md)，UIUXProMax 见[界面实现流程](../../../角色/角色列表/软件研发/开发/前端/前端开发/流程/界面实现.md)，browser-skill 见本文件下表）；不命中不读、不占上下文。

## 已登记 skill 的 DSH 读取方式

| Skill | DSH 读取方式 |
|---|---|
| browser-skill（BrowserSkill，DSH 专属） | 命中入口规则"浏览器操作"行时 read [DSH/skills/browser-skill/](./skills/browser-skill/README.md) 后按步骤执行 |
| 优化流程线 | 按维护方针 Skill 索引 read 该 SKILL.md 后按步骤执行 |
| UA（代码开发协作工具） | 按 UA 场景表 read 对应 `understand-*/SKILL.md` |
| UIUXProMax（ui-ux-pro-max） | 按界面实现流程 read SKILL.md 后按步骤执行（需要 Python 3.x） |
