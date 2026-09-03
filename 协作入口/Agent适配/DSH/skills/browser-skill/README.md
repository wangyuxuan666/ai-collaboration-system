---
所属: 体系
必读: 按需
---

# browser-skill（BrowserSkill 浏览器自动化）— DSH 专属

## 触发规则（什么场景用本 skill）

命中以下任一场景时，**read 本文件后按步骤执行**；不命中不读：

- 需要操作**已登录的浏览器**：打开网页、读取页面内容、抓取数据、填表单、点流程、验证页面、截图。
- 需要登录态、表单填写、动态页面交互或页面截图（与 `协作入口\Agent适配\DSH\入口规则.md`"浏览器操作"行对应）。

本 skill 由 **bsk CLI + 浏览器扩展** 提供（不装 DSH 插件，模型通过 shell 调 `bsk` 命令）。

## 运行环境（本机值 + 检测方法）

| 组件 | 默认约定 | 检测 / 准备方式 |
|---|---|---|
| bsk CLI | `<程序目录>\bin\bsk.exe` | 先 `Get-Command bsk` 确认是否已在 PATH；未找到再查 `<程序目录>\bin\`；仍无 → 见"新电脑搭建"节安装 |
| bsk home（状态目录） | `<程序目录>\bsk-home` | 用 `Get-Command bsk` 定位程序目录后确认实际路径；默认会写 C 盘 `~/.bsk`，本协作体要求不写 C 盘 |
| 自动更新 | 关闭 | 每次调用前设置 `$env:BSK_AUTO_UPDATE='off'`（避免更新检查卡网络） |
| 浏览器扩展 | 浏览器内 | 用户在 Chrome Web Store / Edge 加载项商店安装，打开弹窗变绿即已连接 |
| bsk daemon | 自动 | 任意 `bsk` 命令会自动拉起后台服务；失败先跑 `bsk doctor` |

> 首次调用前：先 `Get-Command bsk` 或按"新电脑搭建"节装好，确定本机 bsk 与状态目录的**实际路径**；后续每次调用前按实际值设置：
> `$env:BSK_HOME='<状态目录实际值>'; $env:BSK_AUTO_UPDATE='off'`
> `<程序目录>` = bsk.exe 所在目录的上一级（bin 的父目录），不是固定值，按本机安装位置填写。

## 新电脑搭建（bsk 缺失/迁移时读）

**何时读**：`bsk` 不存在（`Get-Command bsk` 无结果），或 `bsk doctor` 有红项时。

**步骤**：

1. **定位 bsk.exe**：
   - 已有 bsk 环境：`Get-Command bsk` 拿实际路径，`<程序目录>` = 该路径的上一级的上一级（bin 的父目录）。
   - 无 bsk：下载放入 `<程序目录>\bin\`：
     - 方式 A（推荐）：从旧电脑直接拷贝 `bsk.exe`（单文件，无安装）。
     - 方式 B（重新下载）：拉 GitHub release 的 `version.json` 拿版本号和 sha256 → 下载 `bsk-v<版本>-x86_64-pc-windows-msvc.zip` → 校验 sha256 与 `assets['windows-x64'].sha256` 一致 → 解压出 `bsk.exe` 放入 `<程序目录>\bin\`。**不跑官方 `install.ps1`**（会写 C 盘用户目录、改注册表 PATH、写 `.bashrc`）。
2. **建状态目录** `<程序目录>\bsk-home`（空目录即可，bsk 首次运行自动写）。
3. **浏览器装扩展**：Chrome Web Store / Edge 加载项商店安装 BrowserSkill 扩展，弹窗变绿即已连接。
4. **验证**：`$env:BSK_HOME='<程序目录>\bsk-home'; $env:BSK_AUTO_UPDATE='off'` 后跑 `bsk doctor`，全绿（ok/na）即完成。

**注意**：不写 PATH（始终用完整路径 `<程序目录>\bin\bsk.exe` 调用）；全程不碰 C 盘（状态目录放 `<程序目录>\bsk-home`）；调用约定见上方"运行环境"节。

## 强制流程（每次自动化任务必须走完）

```
1. bsk session start                     → 记下输出的 4 字母 session id
2. 后续所有命令都带 --session <id>
3. bsk session stop <id>                 → 结束时必须执行（出错路径也要）
```

- 应急清理：`bsk session stop --all`
- 多浏览器时：`bsk browsers` 看实例，`bsk session start --browser <实例>` 指定；`--no-focus` 后台开窗口不抢焦点。
- 会话空闲默认 5 分钟超时，**不要依赖超时清理，必须手动 stop**。

## 常用命令（三列：命令 | 用途 | 参数怎么填）

### 诊断

| bsk 命令 | 用途 | 参数怎么填 |
|---|---|---|
| `bsk status` | 连接健康、已连浏览器、活动会话 | 无（任务前先跑一次） |
| `bsk doctor` | 深度诊断与修复提示 | 失败重试一次仍不行时跑 |
| `bsk browsers` | 列出已连接浏览器实例 | 无 |

### 会话

| bsk 命令 | 用途 | 参数怎么填 |
|---|---|---|
| `bsk session start` | 开 Agent 窗口，输出 4 字母 session id | `--no-focus` 后台开；`--browser <实例>` 多浏览器时 |
| `bsk session stop <id>` | 结束会话、关窗口、归还借用标签页 | id=必填；`--all` 停全部 |
| `bsk session list` | 列出活动会话 | 无 |

### 观察（先看页面再用）

| bsk 命令 | 用途 | 参数怎么填 |
|---|---|---|
| `bsk observe` | **首选**：语义页面视图（VOM），含元素 `@eN` 引用 | `--session <id>` |
| `bsk snapshot` | 静态无障碍树回退，observe 不够用时 | `--session <id>` |
| `bsk get-html` | 原始 HTML（token 成本高，最后手段） | `--session <id>` |
| `bsk screenshot` | 截图（视觉/画布/样式判断不了时） | `--session <id>`；`--ref @eN` 截单元素；`--out 路径` 存文件 |
| `bsk console` | 页面 console/异常（只读调试） | `--session <id>`；`--include-stack` |
| `bsk network` | 网络响应与失败（只读调试） | `--session <id>` |

> 顺序：先 `observe`，不够才 `snapshot`，最后才 `get-html`/`screenshot`。**导航后引用失效，必须重新观察再操作。**

### 导航

| bsk 命令 | 用途 | 参数怎么填 |
|---|---|---|
| `bsk navigate <url>` | 跳转 | url=必填；`--wait-until`、`--timeout` |
| `bsk navigate-back` / `bsk navigate-forward` | 历史后退/前进 | `--session <id>` |
| `bsk reload` | 刷新 | `--session <id>`；`--hard` 绕过缓存 |
| `bsk wait-for-navigation` | 等页面加载完 | `--wait-until`、`--timeout` |
| `bsk wait-ms <时长>` | 干等 | 如 `500ms`、`2s`、`1m`；**不带** `--session` |

### 交互（全部带 `--session <id>`）

| bsk 命令 | 用途 | 参数怎么填 |
|---|---|---|
| `bsk click <引用>` | 点击 | `@eN` 引用（优先）或 CSS 选择器；`--button`、`--click-count`、`--modifiers` |
| `bsk hover <引用>` | 悬停（先悬停显示菜单再重新观察） | 同上；`--settle` |
| `bsk fill <引用> --value <文本>` | 清空并输入 | value=必填 |
| `bsk select <引用> --value <值>` | 下拉选择 | 多选可重复 `--value` |
| `bsk press <键>` | 按键/组合键 | 如 `Enter`、`Ctrl+A`；`--ref` 先聚焦 |

### 标签页（带 `--session <id>`）

| bsk 命令 | 用途 | 参数怎么填 |
|---|---|---|
| `bsk tab list` | 列标签页 | `--scope user\|agent\|all`（默认 all） |
| `bsk tab create` | Agent 窗口新建标签页 | `--url`、`--no-active` |
| `bsk tab close <tab-id>` | 关 Agent 标签页 | tab-id=必填 |
| `bsk tab select <tab-id>` | 聚焦 Agent 标签页 | tab-id=必填 |
| `bsk tab borrow <tab-id>` | 借用用户标签页进 Agent 窗口 | 只读操作无需借用；用完**必须** return |
| `bsk tab return <tab-id>` | 归还借用标签页 | 结束会话时未归还的会自动归还 |

### 请求人接管（验证码/登录/OTP/支付确认）

| bsk 命令 | 用途 | 参数怎么填 |
|---|---|---|
| `bsk request-help` | 暂停并请用户操作 | `--session <id> --prompt "让用户做什么"`（必填）；`--title` 标题；`--target @eN` 高亮目标元素；`--timeout 5m` |

- 返回 `outcome`：`continued`=用户完成（视为确认）、`cancelled`=用户取消、`timed_out`=超时、`completed`=完成条件命中、`disabled`=被禁用（不要重试，自主完成或收尾）。
- 用户操作完成后，**重新 `bsk snapshot` 再继续**，不要用旧引用。

### 其他

| bsk 命令 | 用途 | 参数怎么填 |
|---|---|---|
| `bsk window resize` | 调整 Agent 窗口大小 | `--width`、`--height`（100..7680） |
| `bsk emulate` | 模拟移动设备（视口/UA/触控） | `--device iphone-14` 等预设；`--off` 清除；只作用于单标签页 |
| `bsk record` | 录用户操作生成 trace | 高成本场景，一般不用 |
| `bsk evaluate` | 在页面跑 JS | **禁止**在银行/SSO/密码管理器页提取 token/cookie/密钥 |

## 使用规则（什么场景怎么做）

1. **先看再动**：`navigate` 后先 `observe`/`snapshot` 拿 `@eN` 引用，再点击/填写；导航后引用失效要重新观察。
2. **目标达成即停**：任务是有限目标不是漫游浏览。达成即 `bsk session stop`，不做"再检查一下"之类的多余操作；进一步验证是新任务。
3. **受阻不硬闯**：遇到验证码/登录/OTP/支付确认，或同一动作失败两次无进展 → `bsk request-help` 请用户接管，不要盲目重试。
4. **用户标签页只读**：写操作前先借用（`tab borrow`），用完立即 `tab return`；不要长时间占着用户个人窗口。
5. **结束必 stop**：`bsk session stop <id>` 写在收尾（出错路径也要），不依赖空闲超时。

## 红线（违反即停）

1. **不偷凭据**：不在银行、SSO、密码管理器页面用 `bsk evaluate` 提取 localStorage/cookie/授权头。
2. **不长期借用**：用户个人标签页只借当前步骤，用完即还。
3. **不跳过 stop**：永远 `bsk session stop <id>`。
4. **成功即停**：目标达成后不再点击/刷新/导航/反复确认。

## 出错处理

| 退出码 | 含义 | 怎么办 |
|---|---|---|
| 0 | 成功（`evaluate` 的 JS 抛错也算 0，看 `--json` 的 `.ok`） | 继续 |
| 1 | 参数错/未知会话/引用失效 | 改参数；`bsk session list`；重新 snapshot |
| 2 | 协议/传输（服务不可达、IPC 失败） | `bsk doctor`；查扩展是否连接；重试 |
| 3 | 浏览器/CDP 执行失败 | 重试；简化选择器；查标签页是否还在 |
| 4 | 超时 | 加 `--timeout`；试 `--wait-until domcontentloaded` |
| 5 | 命令未实现 | 换命令继续；提示 `bsk update` |

- 任务前先 `bsk status`（扩展连上了吗）；一次重试解决不了就跑 `bsk doctor`。
- 全局参数：`--json`（机器可读输出）、`--quiet`、`-v/-vv`；详细参数看 `bsk <命令> --help`。
