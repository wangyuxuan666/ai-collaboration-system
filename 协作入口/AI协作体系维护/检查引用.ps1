# 检查引用 - 扫描协作体文件间的引用关系、归类与结构问题
# 用法: powershell -File 检查引用.ps1 [-Target 成长|角色] [-LineName 成长]
# 无参数时默认扫描整个协作体

param(
    [string]$Target = "",
    [string]$LineName = "",
    [switch]$All
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)  # AI协作体系 根目录

# ============================================================
# 动态区域跳过清单：内容会动态变化的目录，不要求 frontmatter，
# 不参与归类与孤儿判断（结构改动时只需维护此清单）
# ============================================================
$DynamicDirs = @(
    '知识库\收集箱\收集区', '知识库\收集箱\手动收集区', '知识库\收集箱\暂存区', '知识库\收集箱\已处理',
    '知识库\Wiki\知识', '知识库\raw',
    '工具\MCP', '.obsidian', '.lrnev',
    '自成长\agentbrain\Case-Learnings\Learnings', '自成长\agentbrain\Case-Learnings\_consolidations',
    '自成长\agentbrain\Case-Learnings\Index.md', '自成长\agentbrain\Case-Learnings\log.md'
)

function Test-Dynamic([string]$Rel) {
    $rNorm = $Rel -replace '\\', '/'
    # 知识正文页：路径含 /知识/ 的视为动态正文（Wiki\<领域>\<主题>\知识\...）
    if ($rNorm -match '/知识/') { return $true }
    foreach ($d in $DynamicDirs) {
        $dNorm = $d -replace '\\', '/'
        if ($rNorm -eq $dNorm -or $rNorm.StartsWith($dNorm + '/')) { return $true }
    }
    return $false
}

# 读取 frontmatter 的 所属 / 必读
function Get-Fm($Path) {
    $result = @{ Line = ''; Need = '' }
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 15)
    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
        foreach ($l in $lines[1..($lines.Count - 1)]) {
            if ($l.Trim() -eq '---') { break }
            if ($l -match '^所属:\s*(.+)$') { $result.Line = $Matches[1].Trim() }
            if ($l -match '^必读:\s*(.+)$') { $result.Need = $Matches[1].Trim() }
        }
    }
    return $result
}

if ($Target -and -not (Test-Path -LiteralPath (Join-Path $root $Target))) {
    Write-Output "目标不存在: $Target（相对于 $root）"
    exit 1
}

$scanRoot = if ($Target) { Join-Path $root $Target } else { $root }
$scopeLabel = if ($Target) { $Target } elseif ($LineName) { "线: $LineName" } else { "整个协作体" }

Write-Output "=========================================="
Write-Output "  检查引用 - 范围: $scopeLabel"
Write-Output "=========================================="
Write-Output ""

$files = Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch '\\工具\\MCP\\gitee\\|\\\.obsidian\\|\\\.lrnev\\|\\代码开发\\开发框架使用\\|\\Understand-Anything\\|\\UIUXProMax\\|\\自成长\\agentbrain\\|\\node_modules\\|\\\.deps\\'
}
if (-not $files) {
    Write-Output "范围内没有可检查的 md 文件"
    exit 0
}

$incoming = @{}
$outgoing = @{}
$absoluteRefs = @()
$brokenRefs = @()
$fileMeta = @{}

foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length).TrimStart('\')
    if (Test-Dynamic $rel) { continue }   # 动态区域跳过
    $outgoing[$rel] = @()
    $fileMeta[$rel] = Get-Fm $f.FullName

    $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8)
    $ln = 0
    foreach ($line in $lines) {
        $ln++
        # 1. 绝对路径引用
        foreach ($m in [regex]::Matches($line, 'F:\\AI协作体系\\[^`\)\]\|''\r\n]+')) {
            $p = ($m.Value.Trim() -split '#')[0]
            if ($p -match '<.*>' -or $p -match '\$\{') { continue }
            $absoluteRefs += "${rel}:${ln} :: $($m.Value)"
            if (Test-Path -LiteralPath $p) {
                $targetRel = $p.Substring($root.Length).TrimStart('\')
                $outgoing[$rel] += $targetRel
                if (-not $incoming.ContainsKey($targetRel)) { $incoming[$targetRel] = @() }
                $incoming[$targetRel] += $rel
            } else {
                $brokenRefs += "${rel}:${ln} :: 绝对路径目标不存在 -> $($m.Value)"
            }
        }
        # 2. 相对路径超链接
        foreach ($m in [regex]::Matches($line, '\[[^\]]+\]\(<?([^)<>]+\.md)>?\)')) {
            $raw = $m.Groups[1].Value
            # 跳过网络 URL（https://、http://、gitee.com 等外部链接）
            if ($raw -match '^[a-zA-Z]+://' -or $raw -match '^www\.') { continue }
            $t = [uri]::UnescapeDataString(($raw -split '#')[0]) -replace '/', '\'
            if (-not $t) { continue }
            try {
                $resolved = [System.IO.Path]::GetFullPath((Join-Path (Split-Path $f.FullName -Parent) $t))
            } catch {
                continue   # 无法解析的路径（含非法字符等）跳过，不中断扫描
            }
            $targetRel = $resolved.Substring($root.Length).TrimStart('\')
            if ($resolved.StartsWith($root) -and (Test-Path -LiteralPath $resolved)) {
                $outgoing[$rel] += $targetRel
                if (-not $incoming.ContainsKey($targetRel)) { $incoming[$targetRel] = @() }
                $incoming[$targetRel] += $rel
            } elseif (-not (Test-Path -LiteralPath $resolved)) {
                $brokenRefs += "${rel}:${ln} :: 链接目标不存在 -> $($m.Groups[1].Value)"
            }
        }
    }
    $outgoing[$rel] = @($outgoing[$rel] | Sort-Object -Unique)
}

Write-Output "【文件统计】静态文件: $($fileMeta.Count) 个（动态区域已跳过）"
Write-Output ""

# ============================================================
# 按线归类输出（frontmatter 所属）
# ============================================================
Write-Output "【按线归类】(frontmatter 所属)"
if ($LineName) {
    $lineFiles = @($fileMeta.GetEnumerator() | Where-Object { $_.Value.Line -eq $LineName } | Sort-Object { $_.Key })
    if ($lineFiles) {
        foreach ($e in $lineFiles) {
            $needTag = if ($e.Value.Need) { "[$($e.Value.Need)]" } else { "" }
            Write-Output "  $needTag $($e.Key)"
        }
    } else {
        Write-Output "  线 '$LineName' 无已声明文件（可能未补 frontmatter 或线名不同）"
    }
} else {
    $lineGroups = $fileMeta.GetEnumerator() | Where-Object { $_.Value.Line } | Group-Object { $_.Value.Line } | Sort-Object Name
    foreach ($g in $lineGroups) {
        Write-Output "  [$($g.Name)] $($g.Count) 个文件:"
        foreach ($e in $g.Group | Sort-Object { $_.Key }) {
            $needTag = if ($e.Value.Need) { "[$($e.Value.Need)]" } else { "" }
            Write-Output "    $needTag $($e.Key)"
        }
    }
    $noLine = @($fileMeta.GetEnumerator() | Where-Object { -not $_.Value.Line })
    if ($noLine) {
        Write-Output "  [未声明所属] $($noLine.Count) 个文件（待补 frontmatter）:"
        $noLine | ForEach-Object { Write-Output "    $($_.Key)" }
    }
}
Write-Output ""

# ============================================================
# 高引用目标
# ============================================================
Write-Output "【高引用目标】(被 2 个以上不同文件引用，改动影响面大)"
$highIncoming = @()
foreach ($e in $incoming.GetEnumerator()) {
    $uniqRefs = @($e.Value | Sort-Object -Unique)
    if ($uniqRefs.Count -ge 2) { $highIncoming += [PSCustomObject]@{ Key = $e.Key; Count = $uniqRefs.Count; Refs = $uniqRefs } }
}
$highIncoming = $highIncoming | Sort-Object Count -Descending
if ($highIncoming) {
    foreach ($e in $highIncoming) {
        Write-Output "  $($e.Key) ← $($e.Count) 个文件: $($e.Refs -join ', ')"
    }
} else {
    Write-Output "  无"
}
Write-Output ""

# ============================================================
# 孤儿（静态文件无引用；排除入口/日志/约定文件）
# ============================================================
Write-Output "【孤儿文件】(静态文件无引用；排除入口/约定/模板后)"
$excludePattern = '(^|\\|\/)index\.md$|(^|\\|\/)log\.md$|(^|\\|\/)入口规则\.md$|(^|\\|\/)README\.md$|(^|\\|\/)入口\.md$|(^|\\|\/)AGENTS\.md$|\\Agent-Profile\\|\\模板\\|^协作入口\\AI协作体系维护\\检查引用\.ps1'
$orphans = @()
foreach ($e in $fileMeta.GetEnumerator()) {
    $rel = $e.Key
    if (-not $incoming.ContainsKey($rel) -and $rel -notmatch $excludePattern) {
        $orphans += $rel
    }
}
if ($orphans) { $orphans | ForEach-Object { Write-Output "  $_" } } else { Write-Output "  无" }
Write-Output ""

# ============================================================
# 绝对路径残留 / 断链
# ============================================================
Write-Output "【绝对路径残留】(应改为相对路径)"
if ($absoluteRefs) { $absoluteRefs | ForEach-Object { Write-Output "  $_" } } else { Write-Output "  无" }
Write-Output ""

Write-Output "【断链/失效引用】"
if ($brokenRefs) { $brokenRefs | ForEach-Object { Write-Output "  $_" } } else { Write-Output "  无" }
Write-Output ""

Write-Output "=========================================="
Write-Output "  汇总: 静态文件 $($fileMeta.Count) | 绝对路径 $($absoluteRefs.Count) | 断链 $($brokenRefs.Count) | 孤儿 $($orphans.Count) | 高引用 $($highIncoming.Count)"
Write-Output "=========================================="
if ($brokenRefs.Count -gt 0) { exit 1 }
exit 0
