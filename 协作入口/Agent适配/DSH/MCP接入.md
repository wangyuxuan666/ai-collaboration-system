---
所属: 体系
必读: 按需
---

# DSH MCP 接入

仅在当前需要使用的已登记 MCP 未出现或调用失败时读取本文件；只处理该 MCP。通用处理流程见[工具接入与故障处理 SOP](../README.md)，本文件只列各 MCP 的接入参数。

## DSH 配置

- MCP 实例配置在 `$DSH_HOME/profiles/<profile>/cordis.patch.yml`；先根据当前 profile 确定实际文件，不固定沿用旧环境路径。
- 新增 MCP 实例必须写入 `insert:` 块。顶层条目只用于覆盖或禁用 bundle 已有条目；把新实例写在顶层会因找不到 id 而被丢弃。
- 本地路径必须按协作体当前位置填写；目录迁移或改名后同步更新。
- 修改后可选在 harness 目录运行当前 profile 的 `--dump-config` 确认条目进入组合树；普通配置修改热重载生效、无需重启 DSH，改完新开会话验证工具（仅增删插件包才需重启）。

## agentbrain

- 源码：[agentbrain](../../../工具/MCP/记忆查询工具/agentbrain-main/)
- 记忆库：[自成长数据](../../../自成长/agentbrain/)
- 类型：本地 stdio MCP。
- 命令：当前环境的 Python 可执行文件。
- 参数：`-m agentbrain.cli serve`。
- `PYTHONPATH`：依次包含 `agentbrain-main`、`agentbrain-main/.deps`、`agentbrain-main/.deps/win32/lib`、`agentbrain-main/.deps/win32`；Windows 使用分号分隔。
- `AGENTBRAIN_VAULT`：指向自成长数据目录。
- `PYTHONIOENCODING=utf-8`（避免 Windows GBK 控制台报错）。
- 接入生效后确认 `memory_profile`、`memory_query` 出现，分别进行一次只读调用；两者成功才算完成（普通配置修改热重载生效，新开会话验证；仅增删插件包才需重启）。
- 工具仍未出现时依次检查：组合配置、patch 路径、Python import、`python -m agentbrain.cli serve` 进程。

## Gitee

### 接入路线

- 首选本地二进制：工具已精简为 3 个（`list_user_repos`、`create_repo`、`get_user_info`），说明书已清空；源码在[工具/MCP/gitee](../../../工具/MCP/gitee)，可执行文件准备方法见[安装指引 mcp-gitee 节](../../../工具/MCP/安装指引.md)（本机无 Go 也有免编译办法）。
- 备选远程官方：`https://api.gitee.com/mcp`（免部署，但暴露全部 29 个工具，说明书无法瘦身）。

### 本地接入

- 前提：mcp-gitee 可执行文件已备好（见上方安装指引）；DSH 进程环境能读到 `GITEE_ACCESS_TOKEN`（Windows 用户环境变量；值不写入任何文件）。
- 在当前 profile 的 `cordis.patch.yml`（`$DSH_HOME/profiles/<profile>/cordis.patch.yml`）用 `insert:` 块注册（格式参照同文件 agentbrain 条目）：

```yaml
- insert:
    - id: mcp-gitee
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: gitee-admin
        transport: stdio
        command: '<mcp-gitee 可执行文件路径>'   # 见安装指引；路径以本机实际安装为准，不入库写死
        args: []
        env:
          ENABLED_TOOLSETS: 'list_user_repos,create_repo,get_user_info'
          GITEE_ACCESS_TOKEN: !!js process.env.GITEE_ACCESS_TOKEN
```

- 生效：DSH 对 profile/home `cordis.patch.yml` 的普通修改**热重载生效，无需重启 DSH**（仅增删插件包才需重启）。改完后**新开会话**等待工具出现（形如 `mcp__gitee-admin__get_user_info`），做一次只读调用验证；当前已开的会话不一定刷新工具表。注意：这里的"无需重启"只指**配置文件改动本身**；若 `GITEE_ACCESS_TOKEN` 是在 DSH 启动之后才设置的用户环境变量，DSH 进程环境里还没有它，仍需重启一次 DSH（见下条 token 说明）。
- token 说明：stdio 桥会先移除名称像凭据的环境变量，`GITEE_ACCESS_TOKEN` **不能靠"自动继承"**，必须在本条目 `env:` 里显式注入（上面的 `!!js` 写法，不写明文）。注入前提是 DSH 进程环境里已有该变量：请在启动 DSH 前设置 Windows 用户环境变量；运行中才设置的，需重启一次 DSH 让进程继承。令牌值不得读取、输出或写入任何文件。
- 可选核对：在 harness 目录运行当前 profile 的 `--dump-config`，确认条目进入组合树。

### 远程备选

- 用 `streamable-http` transport 配置 `https://api.gitee.com/mcp`，`Authorization` 头通过 `!!js` 表达式从 `GITEE_ACCESS_TOKEN` 注入（`Authorization: !!js '`Bearer ${process.env.GITEE_ACCESS_TOKEN}`'`），不写入明文令牌；同样要求 DSH 进程环境含该变量。工具为官方全量，无法过滤。

## codegraph

- 用途：代码知识图谱，回答"X 在哪、谁调用谁、改它影响什么"；登记见 [工具/MCP/README.md](../../../工具/MCP/README.md)，流程用法见[代码开发流程](../../../角色/角色列表/项目治理/总控/流程/代码开发流程.md)第 10 节。
- 类型：本地 stdio MCP（npm 全局包 `@colbymchenry/codegraph`）。
- 命令：本机 node 可执行文件；参数：`<npm 全局目录>\@colbymchenry\codegraph\npm-shim.js`、`serve`、`--mcp`（stdio MCP 模式）。
- 项目定位：MCP 模式按客户端的 rootUri 定位项目；目标项目需先 `codegraph init`（生成项目代码根下的 `.codegraph\`）。
- 生效与验证：改 `cordis.patch.yml` 后热重载生效；**新开会话**确认出现 `mcp__codegraph__*` 工具，做一次只读调用（列文件结构或查询符号）才算接入完成。
- 工具未出现时：`codegraph --version` 能运行 → 查 patch 条目与组合配置、新开会话重试；不能运行 → 说明来源与影响、取得用户同意后 `npm i -g @colbymchenry/codegraph`。
- **验证结果（2026-09-11，某官网项目）**：新会话确认出现 `mcp__codegraph__codegraph_explore`；**调用时必须传 `projectPath` = 代码根**（即项目下真正放源码的那层目录，不是项目根）——传项目根会返回"未索引"（`.codegraph\` 在代码根下，MCP 不向上查找）。

## lrnev

- 用途：项目治理（Scene/Spec/ADR/Task、进度与治理欠账体检）；登记见 [工具/MCP/README.md](../../../工具/MCP/README.md)，流程用法见[代码开发流程](../../../角色/角色列表/项目治理/总控/流程/代码开发流程.md)第 10 节。
- 类型：本地 stdio MCP（npm 全局包 `lrnev`，MCP 入口为 `lrnev-mcp`）。
- 命令：本机 node 可执行文件；参数：`<npm 全局目录>\lrnev\bin\lrnev-mcp.mjs`。
- 工作区：项目根需已 `lrnev init`（生成 `.lrnev\`）；工作区定位方式以首次接入验证结果为准，必要时在条目 `env` 或工具参数中显式指定项目根（不把项目路径写进通用模板）。
- 生效与验证：热重载生效后**新开会话**确认出现 `mcp__lrnev__*` 工具，做一次只读调用（如项目状态快照）才算接入完成。
- 工具未出现时：`lrnev --version` 能运行 → 查 patch 条目与工作区初始化、新开会话重试；不能运行 → 取得用户同意后 `npm i -g lrnev`。
- **验证结果（2026-09-11，某官网项目）**：新会话确认出现 `mcp__lrnev__*` 共 33 个工具；但 `project_status` 返回空（scenes/specs 为空）——**MCP 实例是"一进程一工作区"**（`resolveWorkspaceRoot()`：`LRNEV_WORKSPACE` → 向上查找 `.lrnev` → cwd），DSH 全局实例的工作区不随项目会话切换。
- **因此的使用规则**：项目治理操作**以 CLI 为准**（`lrnev -w <项目根> ...`，工作区显式指定）；**不要把项目路径写死进 profile 配置**（会让其他项目会话误用该工作区、读写错项目的治理数据）；确需用 MCP 时再设 `LRNEV_WORKSPACE`，并知悉切换项目必须同步修改该条目。
