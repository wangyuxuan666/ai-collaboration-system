# 检查知识库 - 只读校验 raw、Wiki、metadata、来源、index、log 的确定性一致性
# 用法: powershell -File 检查知识库.ps1
# 依据: 知识库\规范\知识库Schema.md 第 7 节 校验规则
param(
    [string]$KnowledgeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$wikiRoot = Join-Path $KnowledgeRoot 'Wiki'
$rawRoot = Join-Path $KnowledgeRoot 'raw'
$indexPath = Join-Path $wikiRoot 'index.md'
$logPath = Join-Path $wikiRoot 'log.md'
$errors = [System.Collections.Generic.List[string]]::new()

function Add-Error([string]$Message) { $errors.Add($Message) }

# 解析 YAML frontmatter，返回 @{ Data = @{}; Lines = @(); End = -1 }
function Get-FrontMatter([string]$Path) {
    $lines = @(Get-Content -Encoding utf8 -LiteralPath $Path)
    $result = @{ Data = @{}; Lines = $lines; End = -1 }
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        Add-Error "缺少 YAML frontmatter: $Path"
        return $result
    }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $result.End = $i; break }
    }
    if ($result.End -lt 0) {
        Add-Error "frontmatter 未闭合: $Path"
        return $result
    }
    for ($i = 1; $i -lt $result.End; $i++) {
        if ($lines[$i] -match '^([^:\s][^:]*):\s*(.*)$') {
            $result.Data[$Matches[1]] = ($Matches[2] -replace '\s+#.*$', '').Trim()
        }
    }
    return $result
}

# 解析 "[a, b]" 形式的列表字段，返回去空白的路径数组
function Get-ListField([hashtable]$Data, [string]$Field) {
    $result = @()
    if (-not $Data.ContainsKey($Field)) { return $result }
    $value = $Data[$Field]
    if (-not $value -or $value -eq '[]') { return $result }
    foreach ($item in (($value -replace '^\[|\]$', '') -split ',')) {
        $item = $item.Trim()
        if ($item) { $result += $item }
    }
    return $result
}

# 1. 必要路径
foreach ($required in @($wikiRoot, $rawRoot, $indexPath, $logPath)) {
    if (-not (Test-Path -LiteralPath $required)) { Add-Error "缺少必要路径: $required" }
}

# 2. index 正向检查：链接重复、目标存在；记录目标以便逆查
$indexText = if (Test-Path -LiteralPath $indexPath) { Get-Content -Raw -Encoding utf8 -LiteralPath $indexPath } else { '' }
$indexLinks = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$indexTargets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($match in [regex]::Matches($indexText, '\]\(([^)]+\.md)\)')) {
    $link = $match.Groups[1].Value.Replace('\', '/')
    if (-not $indexLinks.Add($link)) { Add-Error "index 链接重复: $link" }
    $resolved = Join-Path $wikiRoot ($link.Replace('/', '\'))
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        [void]$indexTargets.Add($resolved)
    } else {
        Add-Error "index 链接目标不存在: $link"
    }
}

# 3. 知识页检查：路径、metadata、范围、正文小节、来源、index 登记
$wikiPages = @(Get-ChildItem -LiteralPath $wikiRoot -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notin @($indexPath, $logPath) })
foreach ($page in $wikiPages) {
    $relative = $page.FullName.Substring($wikiRoot.Length + 1).Replace('\', '/')
    $segments = $relative -split '/'
    if ($segments.Count -lt 4) { Add-Error "Wiki 路径层级不足（应为 专业领域/主题路径/知识/页面）: $relative"; continue }
    if ($segments[-2] -ne '知识') { Add-Error "知识页不在 /知识/ 目录下: $relative" }

    $fm = Get-FrontMatter $page.FullName
    $data = $fm.Data
    if ($data['类型'] -ne '知识') { Add-Error "知识页类型必须为「知识」: $relative" }
    if (-not $data.ContainsKey('启用') -or ($data['启用'] -ne '是' -and $data['启用'] -ne '否')) {
        Add-Error "知识页「启用」必须为 是/否: $relative"
    } else {
        $enabled = ($data['启用'] -eq '是')
        if ($enabled) {
            if (-not $indexTargets.Contains($page.FullName)) { Add-Error "启用知识页未登记在 index: $relative" }
            $sources = Get-ListField $data '来源'
            if ($sources.Count -eq 0) { Add-Error "启用知识页缺少来源: $relative" }
        } else {
            if ($indexTargets.Contains($page.FullName)) { Add-Error "停用知识页不应登记在 index: $relative" }
        }
    }
    if (-not $data.ContainsKey('范围') -or [string]::IsNullOrWhiteSpace($data['范围'])) {
        Add-Error "知识页缺少「范围」: $relative"
    } else {
        $expectedScope = ($segments[0..($segments.Count - 3)] -join '/')
        if ($data['范围'] -ne $expectedScope) {
            Add-Error "知识页「范围」与路径不一致（$($data['范围']) != $expectedScope）: $relative"
        }
    }
    # 来源目标必须真实存在（相对知识库根目录）
    foreach ($src in (Get-ListField $data '来源')) {
        if (-not (Test-Path -LiteralPath (Join-Path $KnowledgeRoot ($src.Replace('/', '\'))) -PathType Leaf)) {
            Add-Error "知识页来源目标不存在: $src （$relative）"
        }
    }
    # 正文固定小节
    $body = if ($fm.End + 1 -lt $fm.Lines.Count) { $fm.Lines[($fm.End + 1)..($fm.Lines.Count - 1)] -join "`n" } else { '' }
    foreach ($section in @('结论', '触发条件', '做法与验证', '适用条件与边界', '证据与演变', '相关知识')) {
        $pattern = "(?ms)^##\s+$([regex]::Escape($section))\s*\r?\n(.*?)(?=^##\s|\z)"
        if (-not [regex]::Match($body, $pattern).Success) {
            Add-Error "知识页缺少正文小节「$section」: $relative"
        }
    }
}

# 4. raw 来源记录检查：排除 assets 附件目录；只检查来源记录命名模式 YYYY-MM-DD_主题.md
$rawRecords = @(Get-ChildItem -LiteralPath $rawRoot -Recurse -File -Filter '*.md' | Where-Object {
    $_.FullName -notmatch '\\assets\\' -and $_.Name -match '^\d{4}-\d{2}-\d{2}_.+\.md$'
})
foreach ($rec in $rawRecords) {
    $relative = $rec.FullName.Substring($KnowledgeRoot.Length + 1).Replace('\', '/')
    $fm = Get-FrontMatter $rec.FullName
    $data = $fm.Data
    if ($data['类型'] -ne '原始来源') { Add-Error "raw 来源记录类型必须为「原始来源」: $relative" }
    foreach ($field in @('来源名称', '收集日期', '专业领域', '处理状态')) {
        if (-not $data.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($data[$field])) {
            Add-Error "raw 来源记录缺少「$field」: $relative"
        }
    }
    if ($data.ContainsKey('处理状态') -and $data['处理状态'] -notin @('待提炼', '已提炼', '仅归档', '待确认')) {
        Add-Error "raw 处理状态非法（$($data['处理状态'])，应为 待提炼/已提炼/仅归档/待确认）: $relative"
    }
    # 关联Wiki页面与附件路径目标必须真实存在（相对知识库根目录）
    foreach ($field in @('关联Wiki页面', '附件路径')) {
        foreach ($target in (Get-ListField $data $field)) {
            if (-not (Test-Path -LiteralPath (Join-Path $KnowledgeRoot ($target.Replace('/', '\'))) -PathType Leaf)) {
                Add-Error "raw「$field」目标不存在: $target （$relative）"
            }
        }
    }
}

# 5. log 基础格式
if (Test-Path -LiteralPath $logPath) {
    $logText = Get-Content -Raw -Encoding utf8 -LiteralPath $logPath
    if ($logText -notmatch '\| 日期 \| 类型 \| 页面或范围 \| 来源 \| 变更摘要 \|') {
        Add-Error "Wiki/log.md 缺少标准表头"
    }
}

Write-Output "[SUMMARY] Wiki页面=$($wikiPages.Count) raw来源记录=$($rawRecords.Count) index条目=$($indexTargets.Count) 错误=$($errors.Count)"
foreach ($message in $errors) { Write-Output "[ERROR] $message" }
if ($errors.Count -gt 0) { exit 1 }
exit 0
