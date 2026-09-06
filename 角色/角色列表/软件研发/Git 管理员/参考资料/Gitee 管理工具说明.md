---
所属: 角色
必读: 参考
---

# Gitee 管理工具说明

## 适用范围

本说明用于选择 Gitee 组织和仓库管理的执行方式。它记录本机工具能力，不替代角色权限边界、用户确认或资产目录登记要求。

## 本机 MCP

- 服务名称：`gitee-admin`
- 工具目录：[gitee](../../../../../工具/MCP/gitee)
- 当前能力：读取当前用户仓库、创建仓库（个人/组织/企业）、验证身份。
- 创建组织、修改仓库名称、转移仓库不使用 MCP，需通过 Gitee 网页完成。

### 工具

| 工具 | 用途 | 参数怎么填 |
|---|---|---|
| `list_user_repos` | 读取当前用户授权的仓库列表 | 无必填参数；可选过滤：visibility=public/private/all，type=all/owner/personal/member/public/private（type 与 visibility 不同时使用）；page、per_page 分页 |
| `create_repo` | 创建仓库（个人/组织/企业） | owner_type=必填（user/org/enterprise）；name=必填（仓库名）；private=默认 true（私有）；owner_type=org 时 org=组织路径必填；description、path 可选 |
| `get_user_info` | 获取当前登录用户信息（验证 token 和身份） | 无参数 |

## 凭据

- Gitee Token 仅从 Windows 用户环境变量 `GITEE_ACCESS_TOKEN` 读取。
- 不在角色文件、资产目录、项目文件、日志或聊天中记录、显示或索取 Token。
