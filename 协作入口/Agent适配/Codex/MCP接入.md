---
所属: 体系
必读: 按需
---

# Codex MCP 接入

仅在当前需要使用的已登记 MCP 未出现或调用失败时读取本文件；只处理该 MCP。通用处理流程见[工具接入与故障处理 SOP](../README.md)，本文件只列各 MCP 的接入参数。

## agentbrain

- 源码固定使用[协作体内置源码](../../../工具/MCP/记忆查询工具/agentbrain-main)，记忆库固定使用[自成长数据](../../../自成长/agentbrain)。直接使用这两个路径，不执行搜索、下载或重复安装；规定路径不存在时，判定为协作体文件不完整并报告。
- 使用 Codex 自带的 MCP 注册命令写入用户级配置，不直接手工编辑 `config.toml`：`codex mcp add agentbrain --env "PYTHONPATH=<源码目录>;<源码目录>/.deps;<源码目录>/.deps/win32/lib;<源码目录>/.deps/win32" --env "AGENTBRAIN_VAULT=<记忆库目录>" -- <Python路径> -m agentbrain.cli serve`。Windows 路径中的反斜杠按 PowerShell 实际语法填写。
- 注册后用 `codex mcp get agentbrain` 核对 `enabled: true`、命令、参数和环境变量；用 `codex mcp list` 核对服务仍在列表中。
- 重启后确认 `memory_profile`、`memory_query` 出现，分别进行一次只读调用；两者成功才算完成。

## Gitee

### 接入路线

- 首选本地二进制：工具已精简为 3 个（`list_user_repos`、`create_repo`、`get_user_info`），说明书已清空；源码在[工具/MCP/gitee](../../../工具/MCP/gitee)，需先构建或准备可执行文件。
- 备选远程官方：`https://api.gitee.com/mcp`（免部署，但暴露全部 29 个工具，说明书无法瘦身）。

### 本地接入

- 将 Codex 的 `gitee` MCP 配置为本地 stdio：`command` 指向 `mcp-gitee` 可执行文件，`env` 设置 `ENABLED_TOOLSETS=list_user_repos,create_repo,get_user_info`，只暴露这 3 个工具。
- `GITEE_ACCESS_TOKEN` 从环境变量继承，不写入配置明文；不得读取、输出或写入令牌值。
- 重启后确认 3 个工具出现并进行一次只读调用（如 `get_user_info`）；成功才算完成。

### 远程备选

- 配置远程地址 `https://api.gitee.com/mcp`，通过 `bearer_token_env_var = "GITEE_ACCESS_TOKEN"` 注入凭据；工具为官方全量，无法过滤。需要详情时读取[官方 Codex 接入说明](../../../工具/MCP/gitee/docs/install/codex.md)。

## 持久化要求

- 本地 MCP 必须通过 Codex 的 `codex mcp add` 写入 Codex 的用户级永久配置（`<用户目录>\.codex\config.toml`，AI 先用 `echo $HOME` / `$env:USERPROFILE` 定位实际用户目录，不写死用户名路径）；不得只写入临时会话、工作区临时配置或界面状态，也不得把手工追加配置作为最终接入方式。
- 配置完成后先核对配置文件已落盘且内容可读，再提示用户重启 Codex；重启 Codex 后确认工具出现，必要时再用重启电脑验证配置未丢失。
- 若配置文件在重启后被覆盖，先检查 Codex 更新、配置同步或启动脚本，修复覆盖来源后再重复接入。
