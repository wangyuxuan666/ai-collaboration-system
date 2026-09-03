---
所属: 体系
必读: 按需
---

# Hermes MCP 接入

仅在当前需要使用的已登记 MCP 未出现或调用失败时读取本文件；只处理该 MCP。通用处理流程见[工具接入与故障处理 SOP](../README.md)，本文件只列各 MCP 的接入参数。

## agentbrain

- 自行确认[源码](../../../工具/MCP/记忆查询工具/agentbrain-main/)及[记忆库](../../../自成长/agentbrain/)存在，并检查 Hermes 可用的 Python 和依赖。
- 配置本地 stdio MCP：使用可用 Python 执行 `-m agentbrain.cli serve`；`PYTHONPATH` 依次包含源码目录、`.deps`、`.deps/win32/lib`、`.deps/win32`，`AGENTBRAIN_VAULT` 指向记忆库。
- 刷新或重启后确认 `memory_profile`、`memory_query` 出现，分别进行一次只读调用；两者成功才算完成。

## Gitee

### 接入路线

- 首选本地二进制：工具已精简为 3 个（`list_user_repos`、`create_repo`、`get_user_info`），说明书已清空；源码在[工具/MCP/gitee](../../../工具/MCP/gitee)，需先构建或准备可执行文件。
- 备选远程官方：`https://api.gitee.com/mcp`（免部署，但暴露全部 29 个工具，说明书无法瘦身）。

### 本地接入

- 按 Hermes 实际支持的本地 stdio MCP 方式配置 `mcp-gitee`：`command` 指向可执行文件，`env` 设置 `ENABLED_TOOLSETS=list_user_repos,create_repo,get_user_info`，只暴露这 3 个工具；配置方式无法确定时按处理规则暂停询问，不臆造。
- `GITEE_ACCESS_TOKEN` 从环境变量继承，不写入明文；不得读取、输出或写入令牌值。
- 刷新或重启后确认 3 个工具出现并进行一次只读调用（如 `get_user_info`）；成功才算完成。

### 远程备选

- 按 Hermes 实际支持的远程 HTTP MCP 方式配置 `https://api.gitee.com/mcp`，通过 `GITEE_ACCESS_TOKEN` 注入凭据，不写入明文令牌；工具为官方全量，无法过滤。
