#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Harness Engineering · 多工具集成统一入口（Copilot / Claude Code / Codex / ...）。

.DESCRIPTION
    一条命令搞定：把规范文档 vendor 进采用方仓库 + 为指定的 AI 编码工具渲染配置文件。

    默认为"智能交互"模式：
    - 自动探测项目名、主语言、技术栈、测试命令、Lint 命令作为 prompt 默认值
    - 读取上次 manifest 中的填入值，作为最高优先级默认（重装时零输入）
    - 可选字段留空会被填为 `<未配置>`，便于后续 grep 补充
    - `-NonInteractive` / `-Force` 则零 prompt，使用探测结果

    脚本是幂等的：源未变化时再次运行不写任何文件、不发任何提示。

.PARAMETER TargetRepo
    采用方仓库根目录的绝对路径。

.PARAMETER Targets
    要安装的目标工具列表，对应 agents/_integrations/<name>/target.json。
    默认 'copilot'。可多选，例如 'copilot,claude-code'。

.PARAMETER ProjectName, ProjectOneLiner, PrimaryLanguage, TechStack, TestCommand, LintCommand, HarnessRepoRef
    占位符替换值。优先级：CLI 参数 > 上次 manifest > 探测结果 > 交互输入 / 空默认。
    在不是 -NonInteractive / -Force 的情况下，未提供的字段会进入交互提示。

.PARAMETER VendorHarnessTo
    Vendor 目标子目录（相对于 TargetRepo），默认 '.harness-engineering'。
    会把规范文档（agents/、docs/、templates/、README.md）同步进去，让模板里的链接开箱即可点。
    默认与安装清单（manifest.json）合住一个隐藏目录，语义清晰、便于一键卸载。
    在交互模式下未显式传入时，会弹 prompt 让你确认或自定义路径（回车采纳默认）。

.PARAMETER NoVendor
    不 vendor 规范文档。需配合 -HarnessRepoRef 指定外部 URL。

.PARAMETER CopilotAgents
    Copilot 专属：选择安装哪些 Custom Agent（如 'commit-auditor,design-reviewer'）；'all' 全装。
    省略时使用 target.json 里的 default_select；当前默认为空集（不安装任何 Custom Agent）。

.PARAMETER NonInteractive
    零交互。缺位占位符使用探测结果，仍缺则填 `<未配置>`。附带 summary 不询问。

.PARAMETER Force
    隐含 -NonInteractive；同时所有冲突一律覆盖、所有孤儿一律删除，不弹提示。

.PARAMETER NoDelete
    一律不删除孤儿（即便 -Force 也不删）。CI 升级推荐配合此选项。

.PARAMETER DryRun
    只打印将要执行的动作，不写盘。

.EXAMPLE
    # 首次安装（智能探测 + 交互确认）
    ./install.ps1 -TargetRepo D:\Path\To\YourRepo

.EXAMPLE
    # 零交互（探测出什么用什么）
    ./install.ps1 -TargetRepo D:\Path\To\YourRepo -NonInteractive

.EXAMPLE
    # CI 升级（不交互、不删除）
    ./install.ps1 -TargetRepo D:\Path\To\YourRepo -Force -NoDelete
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TargetRepo,

    [string[]]$Targets = @('copilot'),

    [string]$ProjectName,
    [string]$ProjectOneLiner,
    [string]$PrimaryLanguage,
    [string]$TechStack,
    [string]$TestCommand,
    [string]$LintCommand,
    [string]$HarnessRepoRef,

    [string]$VendorHarnessTo = '.harness-engineering',
    [switch]$NoVendor,

    [string[]]$CopilotAgents,

    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$NoDelete,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Force 隐含 NonInteractive
if ($Force) { $NonInteractive = $true }

# ----------------------------------------------------------------------------
# 路径解析
# ----------------------------------------------------------------------------
$RepoRoot = Split-Path -Parent $PSCommandPath
$LibDir = Join-Path $RepoRoot 'scripts/lib'
$IntegrationsRoot = Join-Path $RepoRoot 'agents/_integrations'

. (Join-Path $LibDir 'sync-engine.ps1')
. (Join-Path $LibDir 'target-runner.ps1')
. (Join-Path $LibDir 'detect-defaults.ps1')

if (-not (Test-Path $TargetRepo -PathType Container)) {
    throw "TargetRepo 不存在或不是目录：$TargetRepo"
}
$TargetRepo = (Resolve-Path $TargetRepo).Path

# 读取 harness-engineering 自身版本
$HarnessVersion = '0.0.0'
$versionFile = Join-Path $RepoRoot 'VERSION'
if (Test-Path $versionFile) {
    $HarnessVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
}

# ----------------------------------------------------------------------------
# 验证 targets
# ----------------------------------------------------------------------------
$validTargets = @()
foreach ($t in $Targets) {
    $tDir = Join-Path $IntegrationsRoot $t
    if (-not (Test-Path (Join-Path $tDir 'target.json'))) {
        throw "未知的 target：$t（在 $IntegrationsRoot 下未找到 $t/target.json）"
    }
    $validTargets += @{ Name = $t; Dir = $tDir }
}

# ----------------------------------------------------------------------------
# 占位符收集（CLI > manifest > 探测 > 交互 / 空默认）
# ----------------------------------------------------------------------------

# 1) 探测项目默认值
$detected = Get-ProjectDefaults -Root $TargetRepo

# 2) 读取上次 manifest 中的 replacements（如有）
$priorManifest = $null
$priorReplacements = @{}
$existingManifestPath = Join-Path (Join-Path $TargetRepo '.harness-engineering') 'manifest.json'
if (Test-Path $existingManifestPath) {
    try {
        $priorManifest = Get-Content -LiteralPath $existingManifestPath -Raw | ConvertFrom-Json
        if ($priorManifest.PSObject.Properties.Name -contains 'replacements' -and $priorManifest.replacements) {
            foreach ($prop in $priorManifest.replacements.PSObject.Properties) {
                $priorReplacements[$prop.Name] = [string]$prop.Value
            }
        }
    }
    catch {
        Write-Warning "已存在的 manifest 无法解析，将忽略其中的 replacements：$existingManifestPath"
    }
}

# 3) 解析单字段：CLI > manifest > 探测 > 交互 / 空
function Resolve-Placeholder {
    param(
        [string]$Cli,
        [string]$ManifestKey,
        [string]$Detected,
        [string]$Prompt,
        [bool]$Interactive
    )
    if (-not [string]::IsNullOrWhiteSpace($Cli)) { return $Cli }

    $manifestVal = $null
    if ($priorReplacements.ContainsKey($ManifestKey)) {
        $manifestVal = [string]$priorReplacements[$ManifestKey]
    }

    $default = $null
    if (-not [string]::IsNullOrWhiteSpace($manifestVal)) { $default = $manifestVal }
    elseif (-not [string]::IsNullOrWhiteSpace($Detected)) { $default = $Detected }

    if (-not $Interactive) {
        return $default  # 可能是 $null
    }

    $hint = if ($default) { " [$default]" } else { ' [回车跳过]' }
    $value = Read-Host "$Prompt$hint"
    if ([string]::IsNullOrWhiteSpace($value)) { return $default }
    return $value
}

$Unconfigured = '<未配置>'
$interactive = -not $NonInteractive

Write-Host ''
Write-Host "==> Harness Engineering v$HarnessVersion · 集成同步" -ForegroundColor Cyan
Write-Host "    目标仓库：$TargetRepo"
Write-Host "    安装目标：$($Targets -join ', ')"
Write-Host "    交互模式：$(if ($NonInteractive) { '否' } else { '是' })"

# 探测摘要（仅用于提示用户）
$detectedSummary = @()
foreach ($k in @('ProjectName', 'PrimaryLanguage', 'TechStack', 'TestCommand', 'LintCommand')) {
    if ($detected[$k]) { $detectedSummary += "$k = $($detected[$k])" }
}
if ($detectedSummary) {
    Write-Host ''
    Write-Host '    自动探测：' -ForegroundColor DarkCyan
    foreach ($s in $detectedSummary) { Write-Host "      $s" -ForegroundColor DarkCyan }
}
if ($priorReplacements.Count -gt 0) {
    Write-Host ''
    Write-Host "    检测到上次 manifest（$($priorManifest.harness_version)），将作为默认值预填" -ForegroundColor DarkCyan
}
Write-Host ''

$ProjectName = Resolve-Placeholder -Cli $ProjectName     -ManifestKey 'PROJECT_NAME'      -Detected $detected.ProjectName     -Prompt '项目名称（PROJECT_NAME）'                       -Interactive $interactive
$ProjectOneLiner = Resolve-Placeholder -Cli $ProjectOneLiner -ManifestKey 'PROJECT_ONE_LINER' -Detected ''                        -Prompt '一句话定位（PROJECT_ONE_LINER，可留空）'        -Interactive $interactive
$PrimaryLanguage = Resolve-Placeholder -Cli $PrimaryLanguage -ManifestKey 'PRIMARY_LANGUAGE'  -Detected $detected.PrimaryLanguage -Prompt '主语言（PRIMARY_LANGUAGE，如 C# / TypeScript）'  -Interactive $interactive
$TechStack = Resolve-Placeholder -Cli $TechStack       -ManifestKey 'TECH_STACK'        -Detected $detected.TechStack       -Prompt '技术栈（TECH_STACK，如 .NET 10 + ASP.NET Core）' -Interactive $interactive
$TestCommand = Resolve-Placeholder -Cli $TestCommand     -ManifestKey 'TEST_COMMAND'      -Detected $detected.TestCommand     -Prompt '测试命令（TEST_COMMAND）'                       -Interactive $interactive
$LintCommand = Resolve-Placeholder -Cli $LintCommand     -ManifestKey 'LINT_COMMAND'      -Detected $detected.LintCommand     -Prompt '代码风格检查命令（LINT_COMMAND）'               -Interactive $interactive

# Vendor 目录：CLI 显式传入 > 上次 manifest.vendor_dir > 参数默认值（.harness-engineering）；
# 未显式传入且交互模式 → 弹 prompt，回车采纳默认。
if (-not $NoVendor) {
    if (-not $PSBoundParameters.ContainsKey('VendorHarnessTo')) {
        $vendorDefault = $VendorHarnessTo
        if ($priorManifest -and $priorManifest.PSObject.Properties.Name -contains 'vendor_dir') {
            $priorVendor = [string]$priorManifest.vendor_dir
            if ($priorVendor) { $vendorDefault = $priorVendor }
        }
        if ($interactive) {
            $hint = " [$vendorDefault]"
            $value = Read-Host "Vendor 目录（相对 TargetRepo）$hint"
            if ([string]::IsNullOrWhiteSpace($value)) { $VendorHarnessTo = $vendorDefault } else { $VendorHarnessTo = $value.Trim() }
        }
        else {
            $VendorHarnessTo = $vendorDefault
        }
    }
}

if ($NoVendor) {
    $defaultRef = if ($priorReplacements.ContainsKey('HARNESS_REPO_REF')) { [string]$priorReplacements['HARNESS_REPO_REF'] } else { 'https://github.com/shuaihuadu/harness-engineering' }
    $HarnessRepoRef = Resolve-Placeholder -Cli $HarnessRepoRef -ManifestKey 'HARNESS_REPO_REF' -Detected $defaultRef -Prompt '规范引用（HARNESS_REPO_REF，路径或 URL）' -Interactive $interactive
    if (-not $HarnessRepoRef) { $HarnessRepoRef = $defaultRef }
    $VendorHarnessTo = $null
}
else {
    if (-not $HarnessRepoRef) { $HarnessRepoRef = $VendorHarnessTo }
}

# ProjectName 兜底（避免空字符串）；其余可选字段留空 → 填 <未配置>
if ([string]::IsNullOrWhiteSpace($ProjectName)) { $ProjectName = Split-Path -Leaf $TargetRepo }
foreach ($v in @(@{ N = 'ProjectOneLiner'; R = [ref]$ProjectOneLiner }, @{ N = 'PrimaryLanguage'; R = [ref]$PrimaryLanguage }, @{ N = 'TechStack'; R = [ref]$TechStack }, @{ N = 'TestCommand'; R = [ref]$TestCommand }, @{ N = 'LintCommand'; R = [ref]$LintCommand })) {
    if ([string]::IsNullOrWhiteSpace($v.R.Value)) { $v.R.Value = $Unconfigured }
}
if ([string]::IsNullOrWhiteSpace($HarnessRepoRef)) {
    throw 'HARNESS_REPO_REF 不能为空'
}

$Replacements = [ordered]@{
    'PROJECT_NAME'                 = $ProjectName
    'PROJECT_ONE_LINER'            = $ProjectOneLiner
    'PRIMARY_LANGUAGE'             = $PrimaryLanguage
    'TECH_STACK'                   = $TechStack
    'TEST_COMMAND'                 = $TestCommand
    'LINT_COMMAND'                 = $LintCommand
    'HARNESS_REPO_REF'             = $HarnessRepoRef
    # 派生占位符：从 .github/ 子目录链接回 vendor 时需多一级 ../；URL 则保持原样
    'HARNESS_REPO_REF_FROM_GITHUB' = $(if ($HarnessRepoRef -match '^(https?://|/)') { $HarnessRepoRef } else { "../$HarnessRepoRef" })
}

# 4) 总结 + 确认
Write-Host ''
Write-Host '==> 即将使用以下占位符渲染：' -ForegroundColor Cyan
foreach ($k in $Replacements.Keys) {
    $val = $Replacements[$k]
    $color = if ($val -eq $Unconfigured) { 'Yellow' } else { 'Gray' }
    Write-Host ("    {0,-20} = {1}" -f $k, $val) -ForegroundColor $color
}
$unconfiguredCount = @($Replacements.Values | Where-Object { $_ -eq $Unconfigured }).Count
if ($unconfiguredCount -gt 0) {
    Write-Host ''
    Write-Host "    [!] 有 $unconfiguredCount 项未配置，将渲染为 `<未配置>`；安装后请用以下命令逐一补充：" -ForegroundColor Yellow
    Write-Host "        Get-ChildItem '$TargetRepo/.github' -Recurse -File | Select-String '<未配置>'" -ForegroundColor Yellow
}

if ($interactive) {
    Write-Host ''
    $confirm = Read-Host '继续？[Y/n]'
    if ($confirm -and $confirm.Trim().ToLowerInvariant() -in @('n', 'no')) {
        Write-Host '已取消。' -ForegroundColor DarkYellow
        exit 1
    }
}

# ----------------------------------------------------------------------------
# 上下文 + 选择映射
# ----------------------------------------------------------------------------
$Context = @{
    Force          = [bool]$Force
    NonInteractive = [bool]$NonInteractive
    NoDelete       = [bool]$NoDelete
    DryRun         = [bool]$DryRun
    OverwriteAll   = $false
    DeleteAll      = $false
    Replacements   = $Replacements
    TargetRepo     = $TargetRepo
    Manifest       = [System.Collections.Generic.List[hashtable]]::new()
}

# Selections：target 名 → 用户挑的 stem 列表（含 'all'）
$Selections = @{}
if ($CopilotAgents) {
    $Selections['copilot/custom-agents'] = $CopilotAgents
}

# ----------------------------------------------------------------------------
# 1. Vendor（共享给所有 target）
# ----------------------------------------------------------------------------
if ($VendorHarnessTo) {
    $vendorAbs = Join-Path $TargetRepo $VendorHarnessTo
    Write-Host ''
    Write-Host "==> Vendor 规范文档 -> $vendorAbs" -ForegroundColor Cyan
    Sync-VendoredTree -Context $Context -SourceRoot $RepoRoot -TargetRoot $vendorAbs `
        -Items @('agents', 'docs', 'templates', 'README.md')
}
else {
    Write-Host ''
    Write-Host '==> 跳过 vendor（指定了 -NoVendor）' -ForegroundColor DarkYellow
}

# ----------------------------------------------------------------------------
# 2. 逐个执行 target
# ----------------------------------------------------------------------------
foreach ($t in $validTargets) {
    Invoke-Target -Context $Context -TargetDir $t.Dir -TargetRepoRoot $TargetRepo -Selections $Selections
}

# ----------------------------------------------------------------------------
# 3. 写 manifest（uninstall 依赖此文件）
# ----------------------------------------------------------------------------
$manifestDir = Join-Path $TargetRepo '.harness-engineering'
$manifestPath = Join-Path $manifestDir 'manifest.json'

$harnessCommit = $null
try {
    Push-Location $RepoRoot
    $harnessCommit = (& git rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $harnessCommit = $null }
}
catch { $harnessCommit = $null }
finally { Pop-Location }

# 合并已有 manifest（同路径以本次为准；过去装过但本次未触及的 entry 保留——支持 multi-target 增量安装）
$mergedFiles = @{}
if (Test-Path $manifestPath) {
    try {
        $existing = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($existing.files) {
            foreach ($entry in $existing.files) {
                $mergedFiles[$entry.path] = @{ path = $entry.path; sha256 = $entry.sha256; kind = $entry.kind }
            }
        }
    }
    catch {
        Write-Warning "已存在的 manifest 无法解析，将覆盖：$manifestPath"
    }
}
foreach ($entry in $Context.Manifest) { $mergedFiles[$entry.path] = $entry }

$manifestObj = [ordered]@{
    schema          = 'v1'
    harness_version = $HarnessVersion
    harness_commit  = $harnessCommit
    installed_at    = (Get-Date).ToString('o')
    targets         = @($Targets)
    vendor_dir      = $VendorHarnessTo
    replacements    = $Replacements
    files           = @($mergedFiles.Values | Sort-Object { $_.path })
}

if (-not $DryRun) {
    if (-not (Test-Path $manifestDir)) { New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null }
    $manifestJson = $manifestObj | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($manifestPath, $manifestJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host ''
    Write-Host "==> 已写入 manifest：$manifestPath" -ForegroundColor Cyan
}

# ----------------------------------------------------------------------------
# 完成
# ----------------------------------------------------------------------------
Write-Host ''
if ($DryRun) {
    Write-Host 'DryRun 完成。未写入任何文件。' -ForegroundColor Cyan
}
else {
    Write-Host '完成。下一步建议：' -ForegroundColor Cyan
    Write-Host "  1. cd $TargetRepo"
    if ($VendorHarnessTo) { Write-Host "  2. git status $VendorHarnessTo" }
    Write-Host '  3. git diff 检查修改是否符合预期'
    Write-Host "  4. 检查渲染输出无残留占位符：Get-ChildItem (Join-Path '$TargetRepo' '.github') -Recurse -File | Select-String '\{\{'"
}
Write-Host ''
