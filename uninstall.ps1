#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Harness Engineering · 卸载脚本（基于 manifest）。

.DESCRIPTION
    根据 <TargetRepo>/.harness-engineering/manifest.json 反向移除安装时落下的文件。

    安全策略：
    - 必须存在 manifest，否则报错退出（不"野扫"用户仓库）。
    - 文件已不存在 → 跳过（幂等）。
    - 文件存在且 sha256 与 manifest 一致 → 默认删除（用户未修改）。
    - 文件存在但 sha256 不一致 → 默认保留并列出告警，须加 -Force 才删。
    - 自下而上清理只剩空的目录；非空目录绝不递归删。
    - 全程支持 -DryRun。

.PARAMETER TargetRepo
    采用方仓库根目录的绝对路径。必填。

.PARAMETER Force
    对内容已被本地修改的文件也执行删除。

.PARAMETER DryRun
    只打印将要执行的动作，不写盘。

.EXAMPLE
    ./uninstall.ps1 -TargetRepo D:\Path\To\YourRepo
    ./uninstall.ps1 -TargetRepo D:\Path\To\YourRepo -DryRun
    ./uninstall.ps1 -TargetRepo D:\Path\To\YourRepo -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TargetRepo,

    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path $TargetRepo -PathType Container)) {
    throw "TargetRepo 不存在或不是目录：$TargetRepo"
}
$TargetRepo = (Resolve-Path $TargetRepo).Path

$manifestDir = Join-Path $TargetRepo '.harness-engineering'
$manifestPath = Join-Path $manifestDir 'manifest.json'

if (-not (Test-Path $manifestPath)) {
    throw "未发现 harness-engineering 安装记录：$manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not $manifest.files) {
    Write-Host "manifest 中无 files 记录，仅清理 manifest 自身。" -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host "==> Harness Engineering · 卸载" -ForegroundColor Cyan
Write-Host "    目标仓库：$TargetRepo"
Write-Host "    manifest 版本：$($manifest.harness_version)（commit: $($manifest.harness_commit))"
Write-Host "    待处理文件数：$(@($manifest.files).Count)"
Write-Host ''

# 计算 sha256
function Get-Sha256Hex([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$deleted = 0
$skipped = 0
$kept = 0
$missing = 0
$modifiedKept = New-Object System.Collections.Generic.List[string]
$touchedDirs = New-Object System.Collections.Generic.HashSet[string]

foreach ($entry in @($manifest.files)) {
    $relPath = $entry.path
    $abs = Join-Path $TargetRepo $relPath

    if (-not (Test-Path $abs)) {
        Write-Host "   miss   $relPath (已不存在)" -ForegroundColor DarkGray
        $missing++
        continue
    }

    $currentSha = Get-Sha256Hex $abs
    $clean = ($currentSha -eq $entry.sha256)

    if (-not $clean -and -not $Force) {
        Write-Host "   keep   $relPath (本地已修改，使用 -Force 强制删除)" -ForegroundColor Yellow
        $modifiedKept.Add($relPath) | Out-Null
        $kept++
        continue
    }

    if ($DryRun) {
        Write-Host "   dryrun-delete $relPath" -ForegroundColor DarkGray
    }
    else {
        Remove-Item -LiteralPath $abs -Force
        Write-Host "   delete $relPath" -ForegroundColor Magenta
    }
    $deleted++
    $parent = Split-Path -Parent $abs
    if ($parent) { [void]$touchedDirs.Add($parent) }
}

# 自下而上清理空目录（仅清空，不递归非空）
if (-not $DryRun) {
    $sortedDirs = @($touchedDirs) | Sort-Object -Property Length -Descending
    foreach ($dir in $sortedDirs) {
        $cur = $dir
        while ($cur -and ($cur.Length -gt $TargetRepo.Length) -and (Test-Path $cur -PathType Container)) {
            $items = @(Get-ChildItem -LiteralPath $cur -Force)
            if ($items.Count -gt 0) { break }
            Remove-Item -LiteralPath $cur -Force
            Write-Host "   rmdir  $cur" -ForegroundColor DarkMagenta
            $cur = Split-Path -Parent $cur
        }
    }
}

# manifest 自身：用户未修改且未保留任何 entry → 删 manifest + 目录
$shouldRemoveManifest = ($modifiedKept.Count -eq 0)
if ($DryRun) {
    Write-Host ''
    Write-Host "DryRun 完成。删除 $deleted / 保留 $kept / 缺失 $missing" -ForegroundColor Cyan
}
else {
    if ($shouldRemoveManifest) {
        Remove-Item -LiteralPath $manifestPath -Force
        Write-Host "   delete .harness-engineering/manifest.json" -ForegroundColor Magenta
        if ((Test-Path $manifestDir) -and -not @(Get-ChildItem -LiteralPath $manifestDir -Force)) {
            Remove-Item -LiteralPath $manifestDir -Force
            Write-Host "   rmdir  .harness-engineering" -ForegroundColor DarkMagenta
        }
    }
    else {
        Write-Host ''
        Write-Host "[!] 以下文件被本地修改过，已保留；manifest 也保留：" -ForegroundColor Yellow
        foreach ($p in $modifiedKept) { Write-Host "    $p" }
        Write-Host '    若要强制删除：-Force；若确认保留请手动删除 manifest 自身。' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host "完成。删除 $deleted / 保留 $kept / 缺失 $missing" -ForegroundColor Cyan
}
Write-Host ''
