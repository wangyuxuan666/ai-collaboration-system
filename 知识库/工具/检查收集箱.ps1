param(
    [string]$KnowledgeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$collectionRoot = Join-Path $KnowledgeRoot '收集箱'
$collectionLogPath = Join-Path $collectionRoot '处理记录.md'
$collectionAreas = @('收集区', '手动收集区', '暂存区', '已处理')
$candidateAreas = @('收集区', '暂存区')
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-Error([string]$Message) {
    $script:errors.Add($Message)
}

function Add-Warning([string]$Message) {
    $script:warnings.Add($Message)
}

function Get-FrontMatter([string]$Path) {
    $lines = @(Get-Content -Encoding utf8 -LiteralPath $Path)
    $result = @{ Data = @{}; Lines = $lines; End = -1 }
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        Add-Error "缺少 YAML frontmatter: $Path"
        return $result
    }

    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') {
            $result.End = $i
            break
        }
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

foreach ($requiredPath in @($collectionRoot, $collectionLogPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        Add-Error "缺少必要路径: $requiredPath"
    }
}
foreach ($area in $collectionAreas) {
    $areaPath = Join-Path $collectionRoot $area
    if (-not (Test-Path -LiteralPath $areaPath -PathType Container)) {
        Add-Error "缺少收集箱区域: $areaPath"
    }
}

if (Test-Path -LiteralPath $collectionLogPath -PathType Leaf) {
    $collectionLogText = Get-Content -LiteralPath $collectionLogPath -Raw -Encoding utf8
    $recordMatches = [regex]::Matches($collectionLogText, '(?m)^## \[\d{4}-\d{2}-\d{2}\] .+ \| .+$')
    for ($i = 0; $i -lt $recordMatches.Count; $i++) {
        $start = $recordMatches[$i].Index
        $end = if ($i + 1 -lt $recordMatches.Count) { $recordMatches[$i + 1].Index } else { $collectionLogText.Length }
        $record = $collectionLogText.Substring($start, $end - $start)
        $title = $recordMatches[$i].Value
        if ($record -notmatch '(?m)^\| 项目 \| 结果 \| 目标路径或处理理由 \|$') {
            Add-Error "处理记录缺少结果表头: $title"
        }
        if ($record -notmatch '(?m)^\| .+ \| (raw|暂存区|已处理（仅归档/已废弃）|Wiki) \| .+ \|$') {
            Add-Error "处理记录缺少有效处理结果: $title"
        }
    }
}

$candidates = @()
$candidateIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($area in $candidateAreas) {
    $areaPath = Join-Path $collectionRoot $area
    if (-not (Test-Path -LiteralPath $areaPath -PathType Container)) {
        continue
    }
    foreach ($candidate in @(Get-ChildItem -LiteralPath $areaPath -File -Filter 'KB-*.md')) {
        $candidates += $candidate
        if ($candidate.Name -notmatch '^(KB-\d{8}-\d{3})_.+\.md$') {
            Add-Error "收集候选文件名不符合 KB-YYYYMMDD-NNN_主题.md: $($candidate.FullName)"
            continue
        }
        $candidateId = $Matches[1]
        if (-not $candidateIds.Add($candidateId)) {
            Add-Error "收集候选编号重复: $candidateId"
        }
        $frontMatter = Get-FrontMatter $candidate.FullName
        $data = $frontMatter.Data
        if ($data['类型'] -ne '知识候选') {
            Add-Error "收集候选类型必须为知识候选: $($candidate.FullName)"
        }
        if ($data['候选编号'] -ne $candidateId) {
            Add-Error "收集候选编号与文件名不一致: $($candidate.FullName)"
        }
        foreach ($field in @('提交日期', '提交者', '来源任务', '主题')) {
            if (-not $data.ContainsKey($field) -or -not $data[$field]) {
                Add-Error "收集候选缺少 ${field}: $($candidate.FullName)"
            }
        }
        if ($data['主题'] -eq '[]') {
            Add-Error "收集候选主题不能为空: $($candidate.FullName)"
        }
        $body = if ($frontMatter.End + 1 -lt $frontMatter.Lines.Count) {
            $frontMatter.Lines[($frontMatter.End + 1)..($frontMatter.Lines.Count - 1)] -join "`n"
        } else {
            ''
        }
        foreach ($section in @('候选结论', '来源与证据', '适用条件与疑问')) {
            $pattern = "(?ms)^##\s+$([regex]::Escape($section))\s*\r?\n(.*?)(?=^##\s|\z)"
            $match = [regex]::Match($body, $pattern)
            if (-not $match.Success -or [string]::IsNullOrWhiteSpace($match.Groups[1].Value)) {
                Add-Error "收集候选缺少有效正文小节“$section”: $($candidate.FullName)"
            }
        }
    }
}

foreach ($message in $errors) { Write-Output "[ERROR] $message" }
foreach ($message in $warnings) { Write-Output "[WARN] $message" }
$manualItems = if (Test-Path -LiteralPath (Join-Path $collectionRoot '手动收集区') -PathType Container) { @(Get-ChildItem -LiteralPath (Join-Path $collectionRoot '手动收集区') -Force).Count } else { 0 }
Write-Output "[SUMMARY] 收集候选=$($candidates.Count) 手动投放=$manualItems 错误=$($errors.Count) 警告=$($warnings.Count)"
if ($errors.Count -gt 0) { exit 1 }
exit 0
