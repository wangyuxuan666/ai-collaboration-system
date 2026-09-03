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
- 修改后在 harness 目录运行当前 profile 的 `--dump-config`，确认组合树包含目标条目，再重启 DSH 验证工具。

## agentbrain

- 源码：[agentbrain](../../../工具/MCP/记忆查询工具/agentbrain-main/)
- 记忆库：[自成长数据](../../../自成长/agentbrain/)
- 类型：本地 stdio MCP。
- 命令：当前环境的 Python 可执行文件。
- 参数：`-m agentbrain.cli serve`。
- `PYTHONPATH`：依次包含 `agentbrain-main`、`agentbrain-main/.deps`、`agentbrain-main/.deps/win32/lib`、`agentbrain-main/.deps/win32`；Windows 使用分号分隔。
- `AGENTBRAIN_VAULT`：指向自成长数据目录。
- `PYTHONIOENCODING=utf-8`（避免 Windows GBK 控制台报错）。
- 重启后确认 `memory_profile`、`memory_query` 出现，分别进行一次只读调用；两者成功才算完成。
- 工具仍未出现时依次检查：组合配置、patch 路径、Python import、`python -m agentbrain.cli serve` 进程。

## Gitee

### 接入路线

- 首选本地二进制：工具已精简为 3 个（`list_user_repos`、`create_repo`、`get_user_info`），说明书已清空；源码在[工具/MCP/gitee](../../../工具/MCP/gitee)，需先构建或准备可执行文件。
- 备选远程官方：`https://api.gitee.com/mcp`（免部署，但暴露全部 29 个工具，说明书无法瘦身）。

### 本地接入

- 在 `insert:` 块配置 stdio MCP：`command` 指向 `mcp-gitee` 可执行文件；`env` 设置 `ENABLED_TOOLSETS=list_user_repos,create_repo,get_user_info`，只暴露这 3 个工具。
- `GITEE_ACCESS_TOKEN` 从 Windows 环境变量继承，不在配置中写入明文令牌；不得读取、输出或写入令牌值。
- 在 harness 目录运行当前 profile 的 `--dump-config` 确认条目存在，重启 DSH 后确认 3 个工具出现并进行一次只读调用（如 `get_user_info`）；成功才算完成。

### 远程备选

- 用 `streamable-http` transport 配置 `https://api.gitee.com/mcp`，`Authorization` 头通过 `!!js` 表达式从 `GITEE_ACCESS_TOKEN` 注入，不写入明文令牌；工具为官方全量，无法过滤。
