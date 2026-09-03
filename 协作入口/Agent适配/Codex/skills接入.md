---
所属: 体系
必读: 按需
---

# Codex skills 接入

仅在当前需要使用的已登记 skill 缺失、断链或未发现时读取本文件；只处理该 skill。通用处理流程见[工具接入与故障处理 SOP](../README.md)，本文件只列 Codex 的 skill 加载机制；已登记 skill 清单见[工具/skills/README.md](../../../工具/skills/README.md)。

## 加载机制

- Codex 从 `~/.agents/skills/` 加载 skill（每个 skill 目录须含 `SKILL.md`）。
- 协作体 skill 通过 junction 链接指向 `工具/skills/` 下的源码，更新源码即更新所有平台。
- 协作体 skill 不走平台自动注入；使用时按 skill 各自使用点文档指引 read 对应 `SKILL.md`（UA 场景见[UA 场景表](../../../工具/skills/README.md)，优化流程线见[维护方针 Skill 索引](../../AI协作体系维护/AI协作体系维护方针.md)，UIUXProMax 见[界面实现流程](../../../角色/角色列表/软件研发/开发/前端/前端开发/流程/界面实现.md)），不命中不读。

## 已登记 skill 的平台加载位置

| Skill | Codex 加载位置 |
|---|---|
| 优化流程线 | `~/.agents/skills/优化流程线` → 链接到源码 |
| UA（代码开发协作工具） | `~/.agents/skills/understand` 等 8 个链接（install.ps1 建立） |
| UIUXProMax（ui-ux-pro-max） | `~/.agents/skills/ui-ux-pro-max` → 链接到源码（接入时建立；需要 Python 3.x） |
