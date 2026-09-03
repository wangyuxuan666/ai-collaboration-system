# 第三方代码声明（Third-Party Notices）

本仓库包含以下第三方开源代码，按各项目许可证使用；各许可证全文随源码目录保留。使用者请遵守对应许可证条款。

## 随仓库分发（源码上传）

| 组件 | 位置 | 协议 | 版权 | 原仓库 |
|---|---|---|---|---|
| RuoYi-Vue-Plus（若依前后端） | `代码开发/开发框架使用/若依Plus全配/前端、后端` | MIT | Copyright (c) 2019 RuoYi-Vue-Plus | https://gitee.com/dromara/RuoYi-Vue-Plus |
| v3-admin-vite（纯净骨架前端） | `代码开发/开发框架使用/纯净骨架/前端` | MIT | Copyright (c) 2022-present pany | https://github.com/un-pany/v3-admin-vite |
| weapp-starter（小程序前端） | `代码开发/开发框架使用/小程序/微信小程序/frontend` | MIT | Copyright (c) 2022 樱吹雪 | 见各 frontend/package.json |
| agentbrain（**修改版**） | `工具/MCP/记忆查询工具/agentbrain-main` | Apache-2.0 | agentbrain contributors | https://github.com/2672243194/agentbrain |
| Apache ECharts | `工具/可视化工作台/lib/echarts.min.js` | Apache-2.0 | Apache Software Foundation | https://echarts.apache.org |
| ip2region | `代码开发/开发框架使用/若依Plus全配/后端/ruoyi-admin/src/main/resources/ip2region_v4.xdb` | 以文件随附的上游声明为准 | ip2region contributors | 随 RuoYi-Vue-Plus 分发；上游项目：https://github.com/lionsoul2014/ip2region |

## agentbrain 修改说明

本仓库的 `agentbrain-main` 为基于原版 v0.4.0 的**修改版**（非原版）。改造内容以仓库中现有源码和 README 为准；若需原版请访问原仓库。

若依的 SnailJob 初始化脚本保留了表结构和示例组配置，但已移除固定通信令牌和默认登录账号。部署者需要自行设置 `SNAILJOB_TOKEN`，并按 SnailJob 的初始化流程创建账号。

## 不在仓库内、按引导安装的组件

以下组件源码不随本仓库分发，安装方式见 `工具/MCP/安装指引.md` 与 `工具/skills/安装指引.md`：

| 组件 | 协议 | 原仓库 |
|---|---|---|
| mcp-gitee | MIT | https://gitee.com/oschina/mcp-gitee |
| Understand-Anything | MIT | https://github.com/Egonex-AI/Understand-Anything |
| UIUXProMax | 原仓库未附 LICENSE，使用注意 | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill |
| CodeGraph | 见 npm 包 | npm: `@colbymchenry/codegraph` |
| lrnev | 见 npm 包 | npm: `lrnev` |

> 本文件随仓库维护：新增或移除第三方组件时同步更新。
