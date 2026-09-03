<#
  ============================================================================
  可视化工作台更新数据.ps1 — 可视化工作台 · 体系数据更新脚本
  ============================================================================
  双击入口：人工维护\可视化工作台更新数据.bat（powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\工具\可视化工作台\可视化工作台更新数据.ps1"）
  运行环境：Windows 自带 PowerShell 5.1（Win7 SP1+；本机验证 5.1.19041 可用）

  职责（技术方案总文档 4.1 / 6.1~6.4）：
    1. 定位：$PSScriptRoot（工具\可视化工作台）→ 体系根（上推 2 级）；data.js 输出与 data-static.js 读取均与脚本同目录，不依赖工作目录
    2. 备份：data.js → data.js.bak
    3. 扫描：按 $ScanSpec 定点扫描体系真实目录 → 生成 overview.tree 结构快照（角色/知识库/入口）
    4. 动态同步（用户拍板 2026-09-02）：画像分支 = 实时解析 agentbrain 画像生效文件（Agent-Profile/Mutable-Hints/preferences.md
              全部字段=值）；经验分支 = 实时解析 Case-Learnings/Index.md（case_id → lesson 条目 + 摘要）；
              只读 agentbrain 用于展示，绝不修改生效文件（遵守 agentbrain 数据规则）；
              动态源缺失/解析失败时降级 data-static.js 静态条目，再降级目录文件扫描
    5. 校验：flow.scenes / 画像 / 经验 条目的 relPath 存在性（agentbrain 文件按存在性核对）
    6. 合并：读取 data-static.js（desc/trigger 文案按 id 合并；flow/quickstart 结构原样透传）
    7. 生成：先写临时文件 data.js.tmp（UTF-8 无 BOM）→ 校验 → 覆盖 data.js
    8. 回滚：任一步失败 → 从 data.js.bak 恢复 + 错误提示

  编码约定：
    - 本脚本源码：UTF-8 带 BOM（PS 5.1 正确识别中文）
    - 输出 data.js：UTF-8 无 BOM
    - data-static.js：本机已有文件只读取、绝不覆盖；首次运行缺失时生成公开模板

  边界：
    - 只读扫描体系（F:\AI协作体系），只写入本工作台目录（data.js / data.js.bak / data.js.tmp）
    - 排除：隐藏目录（. 前缀）、$ScanSpec.ExcludeDirNames（.lrnev/.obsidian/agentbrain/AI协作/工作台自身等）
    - 幂等：重复双击总是全量重扫重生成，无副作用
  ============================================================================
#>

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# $ScanSpec：扫描深度 / 白名单 / 基线 集中在此常量区（技术方案 6.3）
# 体系结构调整时改这里即可，页面代码不动。
# ---------------------------------------------------------------------------
$ScanSpec = @{
  RootName          = 'AI协作体系'
  WorkbenchRel      = '工具/可视化工作台'                      # 工作台相对体系根位置（防呆校验，对应 meta.workbenchRelPath）
  MainBranches      = @(
    @{ Id = 'growth'; Name = '自成长';  RelPath = '自成长';  LineType = 'solid';  Trigger = $null },
    @{ Id = 'roles';  Name = '角色体系'; RelPath = '角色';    LineType = 'dashed'; Trigger = '角色触发表达出现时' },
    @{ Id = 'kb';     Name = '知识库';   RelPath = '知识库';  LineType = 'dashed'; Trigger = '需要专业判断/规范时' }
  )
  RoleListRoot      = '角色/角色列表'                           # 7 大类 → 16 角色（目录递归扫描，含子分组）
  RoleCategoryOrder = @('项目治理','产品','软件研发','设计','资料调查','任务执行','系统治理')  # 分类展示顺序（磁盘多出的分类自动追加）
  RoleAssetDirs     = @('流程','专业领域','参考资料','资产目录')  # 角色展开子项（无 md 文件的子目录不显示）
  ProfileRel        = '自成长/用户画像'
  ExpRel            = '自成长/经验'
  WikiRel           = '知识库/Wiki'
  # 画像/经验动态同步源（用户拍板 2026-09-02：双击更新时从记忆实时同步，脚本只读展示、不修改 agentbrain 生效文件）
  ProfileFileRel    = '自成长/agentbrain/Agent-Profile/Mutable-Hints/preferences.md'   # 画像生效文件（front-matter preferences 映射）
  ExpIndexRel       = '自成长/agentbrain/Case-Learnings/Index.md'                       # 经验索引（case_id → lesson + 摘要）
  ExpLearningsRel   = '自成长/agentbrain/Case-Learnings/Learnings'                      # 经验条目文件目录
  ExcludeDirNames   = @('AI协作','可视化工作台','agentbrain','node_modules','.git')  # 排除目录名（隐藏目录另按 '.' 前缀排除）
  Expected          = @{ Categories = 7; Roles = 16; WikiDomains = 4 }   # 基线核对（不符仅告警，不阻断）
  ExpandLevel       = 3
  LineLegend        = '实线=必读 / 虚线=按需+触发条件'
  PlaceholderDesc   = '【占位】{name} 说明待补充（文案产出者待定，请补 data-static.js）'
}

# ---------------------------------------------------------------------------
# 路径定位
# ---------------------------------------------------------------------------
$script:Workbench = $PSScriptRoot                                                          # 工具\可视化工作台（脚本自身目录）
$script:Root      = Split-Path (Split-Path $script:Workbench -Parent) -Parent              # 可视化工作台 → 工具 → 体系根（上推 2 级）
$DataPath = Join-Path $script:Workbench 'data.js'                                          # 输出与 data-static.js 均与脚本同目录
$BakPath  = Join-Path $script:Workbench 'data.js.bak'
$TmpPath  = Join-Path $script:Workbench 'data.js.tmp'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:UsedIds = @{}
$script:StaticDesc = @{}
$script:StaticTrigger = @{}
$script:GeneratedStatic = $false

# ---------------------------------------------------------------------------
# 通用工具函数
# ---------------------------------------------------------------------------
function Write-Info  { param([string]$M) Write-Host $M }
function Write-Warn  { param([string]$M) Write-Host $M -ForegroundColor Yellow }
function Write-Err   { param([string]$M) Write-Host $M -ForegroundColor Red }

# 首次运行时生成公开版静态内容源。模板不包含用户画像、经验、个人资料或本机路径。
function New-PublicStaticFile {
  param([string]$Path)
  $template = @'
/**
 * 可视化工作台 - 静态内容源（首次运行自动生成的公开模板）
 * 本文件只保存公开的展示结构和流程文案；用户画像与经验由本机记忆库动态提供。
 * 如需维护本机展示文案，可直接编辑本文件后重新运行更新脚本。
 */
window.VWB_STATIC = {
  version: "public-template-1.0.0",
  overview: {
    desc: {
      root: "AI 协作体系总入口。",
      growth: "管理用户画像、经验和长期协作记忆。",
      roles: "按任务选择角色和专业流程。",
      kb: "管理可复用知识和原始资料。",
      "g-profile": "本机用户画像；首次运行时为空白。",
      "g-exp": "本机协作经验；首次运行时为空白。"
    },
    trigger: {
      roles: "出现角色触发表达时",
      kb: "需要专业判断或规范时"
    },
    profileEntries: [],
    expCategories: []
  },
  flow: {
    scenes: [
      {
        id: "start",
        title: "开始使用",
        desc: "新窗口先读取协作入口，再按当前任务加载规则。",
        steps: [
          { id: "s1", type: "action", text: "读取协作入口", detail: "先读取协作入口 README，再按其中规则继续。", res: [{ kind: "file", label: "协作入口/README.md" }], relPath: "协作入口/README.md" },
          { id: "s2", type: "action", text: "按任务读取相关内容", detail: "只读取当前任务需要的角色、知识库和工具说明。", res: [{ kind: "file", label: "协作入口/README.md" }], relPath: "协作入口/README.md" },
          { id: "s3", type: "action", text: "开始协作", detail: "缺少工具或依赖时，按安装指引补齐并验证。", res: [{ kind: "file", label: "工具/MCP/安装指引.md" }], relPath: "工具/MCP/安装指引.md", end: true }
        ]
      }
    ]
  },
  quickstart: {
    script: "每次新窗口开始时，先读取 <体系根>\\协作入口\\README.md 并遵守其规则。",
    note: "下载仓库后，将仓库目录交给 AI，并发送上面的启动话术。",
    steps: [
      "复制启动话术",
      "把仓库目录交给 AI",
      "缺少工具时按 AI 提示安装并验证"
    ]
  }
};
'@
  [System.IO.File]::WriteAllText($Path, $template.TrimStart(), $Utf8NoBom)
  $script:GeneratedStatic = $true
  Write-Info "  √ 首次运行已生成公开版 data-static.js（不含个人信息）"
}

# 进度显示（双击 bat 时让用户看到正在加载）
# 双通道：Write-Progress 控制台进度条 + 文本状态滚动（\r 覆盖单行）；100% 时由调用方输出换行结束滚动行
# 注：状态字符用 ASCII「>>」而非 ▶，避免 GBK 控制台（936）无映射显示为 ?
function Show-Progress {
  param([int]$Percent, [string]$Status)
  Write-Progress -Activity '可视化工作台 · 正在更新数据' -Status $Status -PercentComplete $Percent
  Write-Host ("`r  >> {0}  {1}%" -f $Status, $Percent) -NoNewline
}

function Get-RelPath {
  param([string]$FullPath)
  if ($script:Root) { $FullPath = $FullPath.Substring($script:Root.Length).TrimStart('\') }
  return ($FullPath -replace '\\','/')
}

function New-Slug {
  param([string]$Prefix, [string]$Name)
  $slug = ($Name -replace '[^\w-]','')          # 保留 ASCII 字、数字、下划线、中文，去掉空格/符号
  if ([string]::IsNullOrEmpty($slug)) { $slug = 'x' }
  return ($Prefix + '-' + $slug)
}

function New-Node {
  param([string]$Id, [string]$Name, [string]$RelPath, [string]$Desc,
        [string]$LineType, [string]$Trigger, [string]$Type, [switch]$Expandable, [string]$RawChildren)
  if ($script:UsedIds.ContainsKey($Id)) {                       # id 去重（防同一目录同名文件冲突）
    $i = 2
    while ($script:UsedIds.ContainsKey("$Id-$i")) { $i++ }
    $Id = "$Id-$i"
  }
  $script:UsedIds[$Id] = $true
  $n = [ordered]@{ Id = $Id; Name = $Name; RelPath = $RelPath; Desc = $Desc }
  if ($LineType)   { $n.LineType   = $LineType }
  if ($Trigger)    { $n.Trigger    = $Trigger }
  if ($Type)       { $n.Type       = $Type }
  if ($Expandable) { $n.Expandable = $true }
  if ($RawChildren) {
    $n.RawChildren = $RawChildren                              # 静态透传 children（画像/经验内容来自 data-static.js）
  } else {
    $n.Children = New-Object System.Collections.ArrayList
  }
  return $n
}

function Get-NodeDesc {
  param([string]$Id, [string]$Name)
  if ($script:StaticDesc.ContainsKey($Id)) { return $script:StaticDesc[$Id] }
  return ($ScanSpec.PlaceholderDesc -replace '{name}', $Name)
}

# 目录列表：排除隐藏目录（. 前缀）与排除名单
function Get-NodeDirs {
  param([string]$DirPath)
  Get-ChildItem -LiteralPath $DirPath -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '.*' -and $ScanSpec.ExcludeDirNames -notcontains $_.Name } |
    Sort-Object Name
}

# 递归寻找角色目录：目录内含「{目录名}.md」即视为角色目录（如 前端开发/前端开发.md）
function Get-RoleDirs {
  param([string]$DirPath)
  $found = @()
  foreach ($d in (Get-NodeDirs $DirPath)) {
    if (Test-Path -LiteralPath (Join-Path $d.FullName ($d.Name + '.md'))) { $found += $d }
    else { $found += Get-RoleDirs $d.FullName }
  }
  return $found
}

# ---------------------------------------------------------------------------
# JS 转义 / 序列化
# ---------------------------------------------------------------------------
function ConvertTo-JsString {
  param([string]$S)
  if ($null -eq $S) { return '""' }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $S.ToCharArray()) {
    if ($ch -eq '"')      { [void]$sb.Append('\"') }
    elseif ($ch -eq '\')  { [void]$sb.Append('\\') }
    elseif ($ch -eq "`n") { [void]$sb.Append('\n') }
    elseif ($ch -eq "`r") { [void]$sb.Append('\r') }
    elseif ($ch -eq "`t") { [void]$sb.Append('\t') }
    else                  { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}

function ConvertTo-JsNode {
  param($Node, [int]$Indent)
  $pad = ('  ' * $Indent)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("$pad{")
  [void]$sb.Append("`n$pad  id: "      + (ConvertTo-JsString $Node.Id)      + ',')
  [void]$sb.Append("`n$pad  name: "    + (ConvertTo-JsString $Node.Name)    + ',')
  [void]$sb.Append("`n$pad  relPath: " + (ConvertTo-JsString $Node.RelPath) + ',')
  [void]$sb.Append("`n$pad  desc: "    + (ConvertTo-JsString $Node.Desc))
  if ($Node.LineType)   { [void]$sb.Append(",`n$pad  lineType: "   + (ConvertTo-JsString $Node.LineType)) }
  if ($Node.Trigger)    { [void]$sb.Append(",`n$pad  trigger: "    + (ConvertTo-JsString $Node.Trigger)) }
  if ($Node.Type)       { [void]$sb.Append(",`n$pad  type: "       + (ConvertTo-JsString $Node.Type)) }
  if ($Node.Expandable) { [void]$sb.Append(",`n$pad  expandable: true") }
  if ($Node.RawChildren) {
    # 静态透传：children 原样嵌入（画像/经验内容由 data-static.js 维护）
    [void]$sb.Append(",`n$pad  children: " + $Node.RawChildren)
  } elseif ($Node.Children -and $Node.Children.Count -gt 0) {
    [void]$sb.Append(",`n$pad  children: [")
    for ($i = 0; $i -lt $Node.Children.Count; $i++) {
      [void]$sb.Append("`n" + (ConvertTo-JsNode $Node.Children[$i] ($Indent + 2)))
      if ($i -lt $Node.Children.Count - 1) { [void]$sb.Append(',') }
    }
    [void]$sb.Append("`n$pad  ]")
  }
  [void]$sb.Append("`n$pad}")
  return $sb.ToString()
}

# ---------------------------------------------------------------------------
# 解析 data-static.js（字符串/注释感知的括号配平提取，不依赖 JS 引擎）
# ---------------------------------------------------------------------------
function Get-JsBlock {
  # 在 $Text 中（从 $FromIndex 起）查找 $Marker（跳过字符串与注释），
  # 随后提取以 $Open 开头、配平到 $Close 的块文本；找不到返回 $null
  param([string]$Text, [string]$Marker, [char]$Open, [char]$Close, [int]$FromIndex = 0)
  $len = $Text.Length
  $i = $FromIndex
  $state = 'code'
  while ($i -lt $len) {
    $c = $Text[$i]
    $n = if ($i + 1 -lt $len) { $Text[$i + 1] } else { [char]0 }
    switch ($state) {
      'code' {
        if ($c -eq '"') { $state = 'str' }
        elseif ($c -eq "'") { $state = 'str1' }
        elseif ($c -eq '/' -and $n -eq '/') { $state = 'line'; $i++ }
        elseif ($c -eq '/' -and $n -eq '*') { $state = 'block'; $i++ }
        else {
          if (($len - $i -ge $Marker.Length) -and $Text.Substring($i, $Marker.Length) -eq $Marker) {
            $j = $i + $Marker.Length
            while ($j -lt $len -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
            if ($j -lt $len -and $Text[$j] -eq ':') { $j++; while ($j -lt $len -and [char]::IsWhiteSpace($Text[$j])) { $j++ } }
            if ($j -lt $len -and $Text[$j] -eq $Open) {
              $depth = 0; $k = $j; $st = 'code'
              while ($k -lt $len) {
                $c2 = $Text[$k]
                $n2 = if ($k + 1 -lt $len) { $Text[$k + 1] } else { [char]0 }
                switch ($st) {
                  'code' {
                    if ($c2 -eq '"') { $st = 'str' }
                    elseif ($c2 -eq "'") { $st = 'str1' }
                    elseif ($c2 -eq '/' -and $n2 -eq '/') { $st = 'line'; $k++ }
                    elseif ($c2 -eq '/' -and $n2 -eq '*') { $st = 'block'; $k++ }
                    elseif ($c2 -eq $Open)  { $depth++ }
                    elseif ($c2 -eq $Close) {
                      $depth--
                      if ($depth -eq 0) { return @($j, $k) }
                    }
                  }
                  'str'   { if ($c2 -eq '\') { $k++ } elseif ($c2 -eq '"') { $st = 'code' } }
                  'str1'  { if ($c2 -eq '\') { $k++ } elseif ($c2 -eq "'") { $st = 'code' } }
                  'line'  { if ($c2 -eq "`n") { $st = 'code' } }
                  'block' { if ($c2 -eq '*' -and $n2 -eq '/') { $st = 'code'; $k++ } }
                }
                $k++
              }
              throw "解析 data-static.js 失败：$Marker 块括号未配平"
            }
          }
        }
      }
      'str'   { if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $state = 'code' } }
      'str1'  { if ($c -eq '\') { $i++ } elseif ($c -eq "'") { $state = 'code' } }
      'line'  { if ($c -eq "`n") { $state = 'code' } }
      'block' { if ($c -eq '*' -and $n -eq '/') { $state = 'code'; $i++ } }
    }
    $i++
  }
  return $null
}

# 解析 { "k": "v", ... } 映射（desc/trigger 文案表；兼容带引号与不带引号键名）
function Get-StringMap {
  param([string]$Text, [int]$FromIndex, [string]$Key)
  $block = Get-JsBlock $Text $Key '{' '}' $FromIndex
  if (-not $block) { return @{} }
  $sub = $Text.Substring($block[0], $block[1] - $block[0] + 1)
  $map = @{}
  foreach ($m in [regex]::Matches($sub, '(?:"([^"]+)"|([A-Za-z_$][\w$]*))\s*:\s*"((?:[^"\\]|\\.)*)"')) {
    $k = if ($m.Groups[1].Value) { $m.Groups[1].Value } else { $m.Groups[2].Value }
    $map[$k] = $m.Groups[3].Value
  }
  return $map
}

# ---------------------------------------------------------------------------
# 目录扫描 → 树节点
# ---------------------------------------------------------------------------
function New-RoleNode {
  param($RoleDir)
  $roleName = $RoleDir.Name
  $rel      = Get-RelPath $RoleDir.FullName
  $roleId   = New-Slug 'role' $roleName
  $node = New-Node -Id $roleId -Name $roleName -RelPath $rel -Desc (Get-NodeDesc $roleId $roleName) -Type 'role'
  # 简述（角色核心文件）
  $briefFile = Join-Path $RoleDir.FullName ($roleName + '.md')
  if (Test-Path -LiteralPath $briefFile) {
    [void]$node.Children.Add((New-Node -Id (New-Slug $roleId 'brief') -Name '简述' -RelPath (Get-RelPath $briefFile) -Desc (Get-NodeDesc '' '简述') -Type 'file'))
  }
  # 资产子目录（流程/专业领域/参考资料/资产目录；仅含 md 文件的子目录展示）
  foreach ($asset in $ScanSpec.RoleAssetDirs) {
    $assetDir = Join-Path $RoleDir.FullName $asset
    if (-not (Test-Path -LiteralPath $assetDir)) { continue }
    $files = @(Get-ChildItem -LiteralPath $assetDir -File -Filter *.md -Force -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($files.Count -eq 0) { continue }
    $assetNode = New-Node -Id (New-Slug $roleId $asset) -Name $asset -RelPath (Get-RelPath $assetDir) -Desc (Get-NodeDesc '' $asset) -Expandable
    foreach ($f in $files) {
      [void]$assetNode.Children.Add((New-Node -Id (New-Slug $assetNode.Id $f.BaseName) -Name $f.BaseName -RelPath (Get-RelPath $f.FullName) -Desc (Get-NodeDesc '' $f.BaseName) -Type 'file'))
    }
    [void]$node.Children.Add($assetNode)
  }
  return $node
}

function New-Branch {
  param($BranchSpec)
  $trig = $BranchSpec.Trigger
  if ($script:StaticTrigger.ContainsKey($BranchSpec.Id)) { $trig = $script:StaticTrigger[$BranchSpec.Id] }   # trigger 优先取 data-static（6.3：trigger 来自 data-static）
  $branch = New-Node -Id $BranchSpec.Id -Name $BranchSpec.Name -RelPath $BranchSpec.RelPath `
            -Desc (Get-NodeDesc $BranchSpec.Id $BranchSpec.Name) -LineType $BranchSpec.LineType -Trigger $trig
  return $branch
}

# 角色体系分支：7 大类（按 $ScanSpec.RoleCategoryOrder 排序）→ 16 角色
function New-RolesBranch {
  Show-Progress 50 '扫描：角色体系（7 大类 / 16 角色）'
  $branch = New-Branch ($ScanSpec.MainBranches | Where-Object { $_.Id -eq 'roles' })
  $root = Join-Path $script:Root ($ScanSpec.RoleListRoot -replace '/','\')
  $dirs  = @(Get-NodeDirs $root)
  $dirMap = @{}
  foreach ($d in $dirs) { $dirMap[$d.Name] = $d }
  $ordered = New-Object System.Collections.ArrayList
  foreach ($name in $ScanSpec.RoleCategoryOrder) {
    if ($dirMap.ContainsKey($name)) { [void]$ordered.Add($dirMap[$name]); $dirMap.Remove($name) }
  }
  foreach ($d in $dirs) { if ($dirMap.ContainsKey($d.Name)) { [void]$ordered.Add($d) } }
  $catIndex = 0
  $catTotal = $ordered.Count
  foreach ($catDir in $ordered) {
    $catIndex++
    if ($catTotal -gt 0) { Show-Progress (50 + [int]($catIndex * 15 / $catTotal)) ("扫描角色分类：{0}（{1}/{2}）" -f $catDir.Name, $catIndex, $catTotal) }
    $catId = New-Slug 'cat' $catDir.Name
    $catNode = New-Node -Id $catId -Name $catDir.Name -RelPath (Get-RelPath $catDir.FullName) -Desc (Get-NodeDesc $catId $catDir.Name) -Expandable
    foreach ($roleDir in (Get-RoleDirs $catDir.FullName)) {
      [void]$catNode.Children.Add((New-RoleNode $roleDir))
    }
    [void]$branch.Children.Add($catNode)
  }
  Show-Progress 65 '角色体系扫描完成'
  return $branch
}

# ---------------------------------------------------------------------------
# 画像/经验动态同步（用户拍板 2026-09-02：双击更新时从记忆实时同步）
# 只读 agentbrain 生效文件（遵守 agentbrain 数据规则：AI 不修改生效文件，仅读取用于展示）
# ---------------------------------------------------------------------------

# 解析 agentbrain 画像生效文件（preferences.md 的 front-matter preferences 映射）→ 字段=值 条目
# 返回：@(@(字段,值), ...)；值支持多行续行（缩进行追加）；文件缺失/解析失败返回空数组
function Get-ProfileEntries {
  param([string]$FilePath)
  $entries = @()
  if (-not (Test-Path -LiteralPath $FilePath)) { return $entries }
  $inFront = $false
  $inPrefs = $false
  $curKey  = $null
  $curVal  = $null
  foreach ($line in (Get-Content -LiteralPath $FilePath -Encoding UTF8)) {
    if ($line -match '^---\s*$') {
      if (-not $inFront) { $inFront = $true; continue }
      else { break }                                   # front-matter 结束
    }
    if (-not $inFront) { continue }
    if ($line -match '^preferences:\s*$') { $inPrefs = $true; continue }
    if (-not $inPrefs) { continue }
    if ($line -match '^\s+([^:]+):\s*(.*)$') {
      if ($curKey) { $entries += ,@($curKey, $curVal.Trim()) }
      $curKey = $Matches[1].Trim()
      $curVal = $Matches[2]
    } elseif ($curKey) {
      $curVal = $curVal + ' ' + $line.Trim()           # 多行值续行
    }
  }
  if ($curKey) { $entries += ,@($curKey, $curVal.Trim()) }
  return $entries
}

# 解析 Case-Learnings/Index.md 表格（lesson/summary/tags/case/verified/used/failed）→ 按 case_id 分类
# 返回：[ordered]@{ case = @(@{Lesson=..; Summary=..}, ...) }（保持 Index.md 出现顺序）
function Get-ExpCategories {
  param([string]$FilePath)
  $cats = [ordered]@{}
  if (-not (Test-Path -LiteralPath $FilePath)) { return $cats }
  foreach ($line in (Get-Content -LiteralPath $FilePath -Encoding UTF8)) {
    $t = $line.Trim()
    if ($t -notmatch '^\|') { continue }
    if ($t -match '^\|[\s\-:|]+\|$') { continue }                    # 分隔行
    if ($t -match 'lesson.*summary.*tags.*case') { continue }        # 表头
    $parts = @($t.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 4) { continue }
    $lesson = $parts[0]; $summary = $parts[1]; $case = $parts[3]
    if (-not $lesson -or -not $case) { continue }
    if (-not $cats.Contains($case)) { $cats[$case] = New-Object System.Collections.ArrayList }
    [void]$cats[$case].Add(@{ Lesson = $lesson; Summary = $summary })
  }
  return $cats
}

# 自成长分支：用户画像 / 经验（动态同步 agentbrain 记忆 → data-static 静态条目兜底 → 目录文件扫描最后兜底）
function New-GrowthBranch {
  Show-Progress 40 '同步：自成长（用户画像）'
  $branch = New-Branch ($ScanSpec.MainBranches | Where-Object { $_.Id -eq 'growth' })
  # 用户画像：动态解析 agentbrain 画像生效文件（全部字段=值）；文件缺失/无条目时降级为 data-static 静态条目，再降级目录文件扫描
  $profileFile = Join-Path $script:Root ($ScanSpec.ProfileFileRel -replace '/','\')
  $profileEntries = @(Get-ProfileEntries $profileFile)
  if ($profileEntries.Count -gt 0) {
    Show-Progress 42 ('同步画像字段：{0} 条' -f $profileEntries.Count)
    $profileNode = New-Node -Id 'g-profile' -Name '用户画像' -RelPath $ScanSpec.ProfileRel -Desc (Get-NodeDesc 'g-profile' '用户画像') -Expandable
    foreach ($e in $profileEntries) {
      $key = $e[0]; $val = $e[1]
      $short = $val
      if ($short.Length -gt 14) { $short = $short.Substring(0, 14) + '…' }   # 树标签截断；desc 保留完整值
      [void]$profileNode.Children.Add((New-Node -Id (New-Slug 'g-profile' $key) -Name ($key + ' = ' + $short) -RelPath $ScanSpec.ProfileRel -Desc $val))
    }
  } elseif ($script:ProfileEntriesText) {
    $profileNode = New-Node -Id 'g-profile' -Name '用户画像' -RelPath $ScanSpec.ProfileRel -Desc (Get-NodeDesc 'g-profile' '用户画像') -Expandable -RawChildren $script:ProfileEntriesText
  } else {
    $profileNode = New-Node -Id 'g-profile' -Name '用户画像' -RelPath $ScanSpec.ProfileRel -Desc (Get-NodeDesc 'g-profile' '用户画像') -Expandable
    $profileDir = Join-Path $script:Root ($ScanSpec.ProfileRel -replace '/','\')
    foreach ($f in (Get-ChildItem -LiteralPath $profileDir -File -Filter *.md -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
      [void]$profileNode.Children.Add((New-Node -Id (New-Slug 'g-profile' $f.BaseName) -Name $f.BaseName -RelPath (Get-RelPath $f.FullName) -Desc (Get-NodeDesc '' $f.BaseName) -Type 'file'))
    }
  }
  [void]$branch.Children.Add($profileNode)
  # 经验：动态解析 Case-Learnings/Index.md 按 case_id 分类（lesson 条目 + 摘要）；文件缺失/无条目时降级 data-static 静态条目，再降级目录文件扫描
  Show-Progress 45 '同步：自成长（经验）'
  $expIndexFile = Join-Path $script:Root ($ScanSpec.ExpIndexRel -replace '/','\')
  $cats = Get-ExpCategories $expIndexFile
  if ($cats.Count -gt 0) {
    $expNode = New-Node -Id 'g-exp' -Name '经验' -RelPath $ScanSpec.ExpRel -Desc (Get-NodeDesc 'g-exp' '经验') -Expandable
    $catIdx = 0
    foreach ($case in $cats.Keys) {
      $catIdx++
      Show-Progress (45 + [int]($catIdx * 5 / $cats.Count)) ("同步经验分类：{0}（{1}/{2}）" -f $case, $catIdx, $cats.Count)
      $catId = New-Slug 'g-exp' $case
      $catNode = New-Node -Id $catId -Name $case -RelPath $ScanSpec.ExpIndexRel -Desc ("{0} 类经验（{1} 条）。" -f $case, $cats[$case].Count) -Expandable
      foreach ($item in $cats[$case]) {
        $lessonRel = $ScanSpec.ExpLearningsRel + '/' + $item.Lesson + '.md'
        if (-not (Test-Path -LiteralPath (Join-Path $script:Root ($lessonRel -replace '/','\')))) {
          $script:MissingDynamic += $lessonRel
        }
        [void]$catNode.Children.Add((New-Node -Id (New-Slug $catId $item.Lesson) -Name $item.Lesson -RelPath $lessonRel -Desc $item.Summary -Type 'file'))
      }
      [void]$expNode.Children.Add($catNode)
    }
  } elseif ($script:ExpCategoriesText) {
    $expNode = New-Node -Id 'g-exp' -Name '经验' -RelPath $ScanSpec.ExpRel -Desc (Get-NodeDesc 'g-exp' '经验') -Expandable -RawChildren $script:ExpCategoriesText
  } else {
    $expNode = New-Node -Id 'g-exp' -Name '经验' -RelPath $ScanSpec.ExpRel -Desc (Get-NodeDesc 'g-exp' '经验') -Expandable
    $expDir = Join-Path $script:Root ($ScanSpec.ExpRel -replace '/','\')
    foreach ($f in (Get-ChildItem -LiteralPath $expDir -File -Filter *.md -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
      [void]$expNode.Children.Add((New-Node -Id (New-Slug 'g-exp' ('f-' + $f.BaseName)) -Name $f.BaseName -RelPath (Get-RelPath $f.FullName) -Desc (Get-NodeDesc '' $f.BaseName) -Type 'file'))
    }
    foreach ($d in (Get-NodeDirs $expDir)) {
      $subFiles = @(Get-ChildItem -LiteralPath $d.FullName -File -Filter *.md -Force -ErrorAction SilentlyContinue)
      if ($subFiles.Count -eq 0) { continue }
      $subNode = New-Node -Id (New-Slug 'g-exp' ('d-' + $d.Name)) -Name $d.Name -RelPath (Get-RelPath $d.FullName) -Desc (Get-NodeDesc '' $d.Name) -Expandable
      foreach ($sf in ($subFiles | Sort-Object Name)) {
        [void]$subNode.Children.Add((New-Node -Id (New-Slug $subNode.Id $sf.BaseName) -Name $sf.BaseName -RelPath (Get-RelPath $sf.FullName) -Desc (Get-NodeDesc '' $sf.BaseName) -Type 'file'))
      }
      [void]$expNode.Children.Add($subNode)
    }
  }
  [void]$branch.Children.Add($expNode)
  Show-Progress 50 '自成长同步完成'
  return $branch
}

# 知识库分支：Wiki 4 领域 → 知识页（递归 *.md）
function New-KbBranch {
  Show-Progress 65 '扫描：知识库（Wiki 领域）'
  $branch = New-Branch ($ScanSpec.MainBranches | Where-Object { $_.Id -eq 'kb' })
  $wikiDir = Join-Path $script:Root ($ScanSpec.WikiRel -replace '/','\')
  $domains = @(Get-NodeDirs $wikiDir)
  $domIndex = 0
  foreach ($domain in $domains) {
    $domIndex++
    if ($domains.Count -gt 0) { Show-Progress (65 + [int]($domIndex * 15 / $domains.Count)) ("扫描知识库领域：{0}（{1}/{2}）" -f $domain.Name, $domIndex, $domains.Count) }
    $domainId = New-Slug 'kb-wiki' $domain.Name
    $domainNode = New-Node -Id $domainId -Name $domain.Name -RelPath (Get-RelPath $domain.FullName) -Desc (Get-NodeDesc $domainId $domain.Name) -Expandable
    foreach ($f in (Get-ChildItem -LiteralPath $domain.FullName -Recurse -File -Filter *.md -Force -ErrorAction SilentlyContinue | Sort-Object FullName)) {
      [void]$domainNode.Children.Add((New-Node -Id (New-Slug $domainId ('p-' + $f.BaseName)) -Name $f.BaseName -RelPath (Get-RelPath $f.FullName) -Desc (Get-NodeDesc '' $f.BaseName) -Type 'file'))
    }
    [void]$branch.Children.Add($domainNode)
  }
  Show-Progress 80 '知识库扫描完成'
  return $branch
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
try {
  Show-Progress 0 '正在启动…'
  Write-Info ''
  Write-Info '=================================================='
  Write-Info ' 可视化工作台 · 数据更新脚本（可视化工作台更新数据.ps1）'
  Write-Info '=================================================='
  Write-Info ''

  # 0. 定位与防呆
  if ([string]::IsNullOrEmpty($script:Workbench)) { throw '无法定位脚本自身路径（$PSScriptRoot 为空），请通过 人工维护\可视化工作台更新数据.bat 双击运行' }
  $wbRel = Get-RelPath $script:Workbench
  if ($wbRel -ne $ScanSpec.WorkbenchRel) {
    throw "工作台位置异常：期望位于「$($ScanSpec.WorkbenchRel)」，实际「$wbRel」。请确认工作台目录位于 工具\可视化工作台\ 下。"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $script:Root '协作入口\README.md'))) {
    throw "体系根校验失败：$script:Root 下未找到 协作入口\README.md"
  }
  Write-Info ("  体系根     : {0}" -f $script:Root)
  Write-Info ("  工作台     : {0}" -f $script:Workbench)
  Show-Progress 10 '定位与校验完成'

  # 1. 读取 data-static.js（已有文件只读；缺失时先生成公开模板）
  Show-Progress 15 '读取 data-static.js'
  $staticPath = Join-Path $script:Workbench 'data-static.js'
  if (-not (Test-Path -LiteralPath $staticPath)) { New-PublicStaticFile $staticPath }
  $staticRaw = [System.IO.File]::ReadAllText($staticPath, [System.Text.Encoding]::UTF8)

  $ovBlock = Get-JsBlock $staticRaw 'overview' '{' '}'
  if (-not $ovBlock) { throw '解析 data-static.js 失败：未找到 overview 块' }
  $script:StaticDesc     = Get-StringMap $staticRaw $ovBlock[0] 'desc'
  $script:StaticTrigger  = Get-StringMap $staticRaw $ovBlock[0] 'trigger'
  $flowBlock  = Get-JsBlock $staticRaw 'flow' '{' '}'
  if (-not $flowBlock) { throw '解析 data-static.js 失败：未找到 flow 块' }
  $flowText   = $staticRaw.Substring($flowBlock[0], $flowBlock[1] - $flowBlock[0] + 1)
  $quickBlock = Get-JsBlock $staticRaw 'quickstart' '{' '}'
  if (-not $quickBlock) { throw '解析 data-static.js 失败：未找到 quickstart 块' }
  $quickText  = $staticRaw.Substring($quickBlock[0], $quickBlock[1] - $quickBlock[0] + 1)

  # flow.scenes relPath 存在性校验（6.3：脚本不生成场景语义，只校验）
  $scenesBlock = Get-JsBlock $staticRaw 'scenes' '[' ']'
  $scenesRelPaths = @()
  if ($scenesBlock) {
    $scenesText = $staticRaw.Substring($scenesBlock[0], $scenesBlock[1] - $scenesBlock[0] + 1)
    $scenesRelPaths = @([regex]::Matches($scenesText, 'relPath\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  }
  # 画像/经验静态条目（用户拍板 2026-09-02：总览树展示真实内容；内容源 data-static.js，脚本只读透传，不扫描 agentbrain 内部）
  $script:ProfileEntriesText = $null
  $script:ExpCategoriesText  = $null
  $profileBlock = Get-JsBlock $staticRaw 'profileEntries' '[' ']' $ovBlock[0]
  if ($profileBlock) { $script:ProfileEntriesText = $staticRaw.Substring($profileBlock[0], $profileBlock[1] - $profileBlock[0] + 1) }
  $expBlock = Get-JsBlock $staticRaw 'expCategories' '[' ']' $ovBlock[0]
  if ($expBlock) { $script:ExpCategoriesText = $staticRaw.Substring($expBlock[0], $expBlock[1] - $expBlock[0] + 1) }
  # 画像/经验条目 relPath 存在性校验（与 flow 同规则：agentbrain 文件按存在性核对）
  $staticRelPaths = @()
  if ($script:ProfileEntriesText) {
    $staticRelPaths += [regex]::Matches($script:ProfileEntriesText, 'relPath\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
  }
  if ($script:ExpCategoriesText) {
    $staticRelPaths += [regex]::Matches($script:ExpCategoriesText, 'relPath\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
  }
  $staticRelPaths = @($staticRelPaths | Sort-Object -Unique)
  $missingPaths = @()
  foreach ($rp in ($scenesRelPaths + $staticRelPaths)) {
    if (-not (Test-Path -LiteralPath (Join-Path $script:Root ($rp -replace '/','\')))) { $missingPaths += $rp }
  }
  $script:MissingDynamic = @()    # 动态同步（画像/经验）阶段发现的缺失 relPath，由 New-GrowthBranch 追加
  $sceneCount = 0
  if ($scenesBlock) {
    $sceneCount = @([regex]::Matches($scenesText, 'title:\s*"')).Count   # 场景数 = 顶层场景对象数（步骤无 title 字段）
  }
  Show-Progress 35 'flow/画像/经验 relPath 校验完成'

  # 2. 扫描体系真实结构 → overview.tree
  $tree = New-Node -Id 'root' -Name $ScanSpec.RootName -RelPath '' -Desc (Get-NodeDesc 'root' $ScanSpec.RootName)
  [void]$tree.Children.Add((New-GrowthBranch))
  [void]$tree.Children.Add((New-RolesBranch))
  [void]$tree.Children.Add((New-KbBranch))

  # 3. 统计（供展示与基线核对；画像/经验为静态透传时按条目 id 计数）
  $catCount = $tree.Children[1].Children.Count
  $roleCount = 0
  foreach ($cat in $tree.Children[1].Children) { $roleCount += $cat.Children.Count }
  $domainCount = $tree.Children[2].Children.Count
  $wikiPageCount = 0
  foreach ($dom in $tree.Children[2].Children) { $wikiPageCount += $dom.Children.Count }
  $profileNodeG = $tree.Children[0].Children[0]
  $expNodeG     = $tree.Children[0].Children[1]
  if ($profileNodeG.RawChildren) {
    $profileCount = @([regex]::Matches($profileNodeG.RawChildren, 'id:\s*"')).Count   # 画像条目数（静态透传）
  } else { $profileCount = $profileNodeG.Children.Count }
  if ($expNodeG.RawChildren) {
    $expCount = @([regex]::Matches($expNodeG.RawChildren, '^\s*id:\s*"', [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count   # 经验分类数（顶层条目，静态透传）
  } else { $expCount = $expNodeG.Children.Count }
  $updatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm'
  Show-Progress 80 '合并文案与生成 data.js'

  # 4. 组装输出
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("/**`n")
  [void]$sb.Append(" * 可视化工作台 - 体系数据文件（由「可视化工作台更新数据.ps1」自动生成，请勿手工编辑）`n")
  [void]$sb.Append(" * ------------------------------------------------------------------`n")
  [void]$sb.Append(" * 数据来源：扫描体系真实目录结构 + 合并 data-static.js（人工维护内容）。`n")
  [void]$sb.Append(" * 需要修改说明文案 / flow 场景 / 话术时，请编辑 data-static.js 后重新运行本脚本。`n")
  [void]$sb.Append(" * 编码：UTF-8 无 BOM。`n")
  [void]$sb.Append(" */`n")
  [void]$sb.Append("window.VWB_DATA = {`n")
  [void]$sb.Append("  meta: {`n")
  [void]$sb.Append("    updatedAt: " + (ConvertTo-JsString $updatedAt) + ",`n")
  [void]$sb.Append("    rootName: " + (ConvertTo-JsString $ScanSpec.RootName) + ",`n")
  [void]$sb.Append("    workbenchRelPath: " + (ConvertTo-JsString $ScanSpec.WorkbenchRel) + "`n")
  [void]$sb.Append("  },`n")
  [void]$sb.Append("`n  overview: {`n")
  [void]$sb.Append("    expandLevel: " + $ScanSpec.ExpandLevel + ",`n")
  [void]$sb.Append("    lineLegend: " + (ConvertTo-JsString $ScanSpec.LineLegend) + ",`n")
  [void]$sb.Append("    tree: " + (ConvertTo-JsNode $tree 0) + "`n")
  [void]$sb.Append("  },`n")
  [void]$sb.Append("`n  flow: " + $flowText + ",`n")
  [void]$sb.Append("`n  quickstart: " + $quickText + "`n")
  [void]$sb.Append("};`n")

  # 5. 先写临时文件（UTF-8 无 BOM）→ 校验 → 备份 → 覆盖
  Show-Progress 85 '写入临时文件 data.js.tmp'
  [System.IO.File]::WriteAllText($TmpPath, $sb.ToString(), $Utf8NoBom)
  $check = [System.IO.File]::ReadAllText($TmpPath, $Utf8NoBom)
  if (-not $check.Contains('window.VWB_DATA = {')) { throw '生成结果校验失败：缺少 window.VWB_DATA' }
  if (-not $check.Contains('updatedAt'))            { throw '生成结果校验失败：缺少 meta.updatedAt' }
  if (-not $check.Contains('flow: {') -or -not $check.Contains('scenes:')) { throw '生成结果校验失败：缺少 flow.scenes' }
  if (-not $check.Contains('quickstart: {'))        { throw '生成结果校验失败：缺少 quickstart' }
  $openB  = ($check.ToCharArray() | Where-Object { $_ -eq '{' }).Count
  $closeB = ($check.ToCharArray() | Where-Object { $_ -eq '}' }).Count
  if ($openB -ne $closeB) {
    Write-Warn ("  [警告] 生成结果花括号不配平（{0} vs {1}），继续前请人工核对 data.js" -f $openB, $closeB)
  }

  Show-Progress 92 '生成结果校验通过'
  if (Test-Path -LiteralPath $DataPath) { Copy-Item -LiteralPath $DataPath -Destination $BakPath -Force }   # 备份
  if (Test-Path -LiteralPath $DataPath) { Remove-Item -LiteralPath $DataPath -Force }
  Move-Item -LiteralPath $TmpPath -Destination $DataPath                                                     # 覆盖
  Show-Progress 95 '备份与覆盖完成'

  # 6. 输出结果
  Show-Progress 100 '完成'
  Write-Progress -Activity '可视化工作台 · 正在更新数据' -Completed
  Write-Info ''
  Write-Info '  —— 扫描结果 ——'
  Write-Info ("    主分支      : {0}（自成长 / 角色体系 / 知识库）" -f $tree.Children.Count)
  Write-Info ("    角色大类    : {0}" -f $catCount)
  Write-Info ("    角色        : {0}" -f $roleCount)
  Write-Info ("    画像条目    : {0}（memory_profile 动态同步）" -f $profileCount)
  Write-Info ("    经验分类    : {0}（Case-Learnings 动态同步）" -f $expCount)
  Write-Info ("    Wiki 领域  : {0}" -f $domainCount)
  Write-Info ("    Wiki 知识页 : {0}" -f $wikiPageCount)
  Write-Info ("    flow 场景  : {0}（结构来自 data-static.js，脚本未改动）" -f $sceneCount)
  $allMissing = @($missingPaths) + @($script:MissingDynamic)
  if ($allMissing.Count -eq 0) {
    Write-Info "    relPath 校验 : 全部存在 √"
  } else {
    Write-Warn ("    relPath 校验 : {0} 条失效（页面将降级显示）：" -f $allMissing.Count)
    foreach ($mp in ($allMissing | Sort-Object -Unique)) { Write-Warn ("      - {0}" -f $mp) }
  }
  Write-Info ''
  Write-Info ("  —— 基线核对（$($ScanSpec.Expected.Categories)/$($ScanSpec.Expected.Roles)/$($ScanSpec.Expected.WikiDomains)） ——")
  if ($catCount -eq $ScanSpec.Expected.Categories -and $roleCount -eq $ScanSpec.Expected.Roles -and $domainCount -eq $ScanSpec.Expected.WikiDomains) {
    Write-Info '    与验收基线一致 √（7 大类 / 16 角色 / 4 领域）'
  } else {
    Write-Warn "    与验收基线不一致（当前 $catCount 大类 / $roleCount 角色 / $domainCount 领域），请核对体系结构是否调整或检查 $ScanSpec"
  }
  Write-Info ''
  Write-Info ("  √ data.js 已更新（最后更新时间 {0}）" -f $updatedAt)
  Write-Info ("  √ 备份已生成：data.js.bak（如需回滚可恢复）")
  Write-Info '  √ 输出编码：UTF-8 无 BOM'
  Write-Info ''
  Write-Info '  请刷新页面查看最新内容（最后更新时间显示在页面底部）。'
  Write-Info '=================================================='
  Write-Host ''
  Write-Host '  √ 已更新完成！data.js 已刷新，可关闭本窗口。' -ForegroundColor Green
  Write-Host ''
  exit 0
}
catch {
  Write-Progress -Activity '可视化工作台 · 正在更新数据' -Completed
  Write-Err ''
  Write-Err ('× 更新失败：' + $_.Exception.Message)
  if ($_.ScriptStackTrace) { Write-Err ('    位置：' + ($_.ScriptStackTrace -split "`n")[0]) }
  if (Test-Path -LiteralPath $BakPath) {
    try {
      Copy-Item -LiteralPath $BakPath -Destination $DataPath -Force
      Write-Warn '  √ 已从 data.js.bak 回滚原数据，页面可继续使用旧数据。'
    } catch { Write-Err ('  × 回滚失败：' + $_.Exception.Message + '（请手工恢复 data.js.bak）') }
  } else {
    Write-Warn '  未找到 data.js.bak（首次运行或原 data.js 不存在），无回滚数据。'
  }
  if (Test-Path -LiteralPath $TmpPath) { Remove-Item -LiteralPath $TmpPath -Force -ErrorAction SilentlyContinue }
  Write-Host ''
  Write-Host '  × 未更新完成！请查看上方错误信息；原数据已尽量恢复。' -ForegroundColor Red
  Write-Err '=================================================='
  exit 1
}
