#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Harness Engineering · 多工具集成统一入口（Copilot / Claude Code / Codex / ...）。

.DESCRIPTION
    一条命令搞定：把规范文档 vendor 进采用方仓库 + 为指定的 AI 编码工具渲染配置文件。

    默认为"智能交互"模式：
    - 自动探测测试命令、Lint 命令作为 prompt 默认值
    - 读取上次 manifest 中的填入值，作为最高优先级默认（重装时零输入）
    - 测试 / Lint 命令以"常用命令菜单 + 自定义"方式提示，回车即采纳推荐
    - 可选字段留空会被填为 `<未配置>`，便于后续 grep 补充
    - `-NonInteractive` / `-Force` 则零 prompt，使用探测结果

    脚本是幂等的：源未变化时再次运行不写任何文件、不发任何提示。

.PARAMETER TargetRepo
    采用方仓库根目录的绝对路径。

.PARAMETER Targets
    要安装的目标工具列表，对应 agents/_integrations/<name>/target.json。
    默认 'copilot'。可多选，例如 'copilot,claude-code'。

.PARAMETER TestCommand, LintCommand, HarnessRepoRef
    占位符替换值。优先级：CLI 参数 > 上次 manifest > 探测结果 > 交互输入 / 空默认。
    在不是 -NonInteractive / -Force 的情况下，未提供的字段会进入交互提示。

.PARAMETER VendorHarnessTo
    Vendor 目标子目录（相对于 TargetRepo），默认 '.he'。
    会把规范文档（HANDBOOK、docs/{stages,repo-layout,tech-debt-gc}.md、README、uninstall.ps1）同步进去，让模板里的链接开箱即可点。
    默认与安装清单（manifest.json）合住一个隐藏目录，语义清晰、便于一键卸载。
    在交互模式下未显式传入时，会弹 prompt 让你确认或自定义路径（回车采纳默认）。

.PARAMETER NoVendor
    不 vendor 规范文档。需配合 -HarnessRepoRef 指定外部 URL。

.PARAMETER CopilotAgents
    Copilot 专属：选择安装哪些 Custom Agent（如 'h3-design-reviewer,h5-coding-executor'）；'all' 全装；'none' 一个不装。
    省略时使用 target.json 里的 default_select；当前默认为 'all'（全装 12 个 Agent，覆盖 H1–H6 与横切阶段，并启用孤儿检测）。

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

    [string]$TestCommand,
    [string]$LintCommand,
    [string]$HarnessRepoRef,

    [string]$VendorHarnessTo = '.he',
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
$priorManifestVendorDir = $null
$existingManifestPath = $null
# 优先按 CLI 显式 VendorHarnessTo 寻 manifest；否则尝试默认 .he/，再退化扫描顶层目录
if ($PSBoundParameters.ContainsKey('VendorHarnessTo') -and $VendorHarnessTo) {
    $candidate = Join-Path (Join-Path $TargetRepo $VendorHarnessTo) 'manifest.json'
    if (Test-Path $candidate) { $existingManifestPath = $candidate; $priorManifestVendorDir = $VendorHarnessTo }
}
if (-not $existingManifestPath) {
    $candidate = Join-Path (Join-Path $TargetRepo '.he') 'manifest.json'
    if (Test-Path $candidate) { $existingManifestPath = $candidate; $priorManifestVendorDir = '.he' }
}
if (-not $existingManifestPath) {
    # 顶层目录扫一圈：识别 schema=v1 + harness_version 的 manifest（自定义 vendor_dir 场景）
    Get-ChildItem -LiteralPath $TargetRepo -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $candidate = Join-Path $_.FullName 'manifest.json'
        if (-not $existingManifestPath -and (Test-Path $candidate)) {
            try {
                $probe = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json
                if ($probe.schema -eq 'v1' -and $probe.harness_version) {
                    $existingManifestPath = $candidate
                    $priorManifestVendorDir = if ($probe.vendor_dir) { [string]$probe.vendor_dir } else { $_.Name }
                }
            }
            catch {}
        }
    }
}
if ($existingManifestPath -and (Test-Path $existingManifestPath)) {
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

    $hint = if ($default) { " [$default]" } else { ' [回车跳过 / press Enter to skip]' }
    $value = Read-Host "$Prompt$hint"
    if ([string]::IsNullOrWhiteSpace($value)) { return $default }
    return $value
}

# 3b) 命令选择：菜单 + 自定义 + 跳过；优先级同 Resolve-Placeholder
#     非交互模式直接走 manifest > detected 的回退链，与 Resolve-Placeholder 等价
function Resolve-CommandWithMenu {
    param(
        [string]$Cli,
        [string]$ManifestKey,
        [string]$Detected,
        [string]$Title,
        [string[]]$Options,
        [bool]$Interactive
    )
    if (-not [string]::IsNullOrWhiteSpace($Cli)) { return $Cli }

    $manifestVal = $null
    if ($priorReplacements.ContainsKey($ManifestKey)) {
        $manifestVal = [string]$priorReplacements[$ManifestKey]
    }

    $preferred = $null
    if (-not [string]::IsNullOrWhiteSpace($manifestVal)) { $preferred = $manifestVal }
    elseif (-not [string]::IsNullOrWhiteSpace($Detected)) { $preferred = $Detected }

    if (-not $Interactive) {
        return $preferred  # 可能是 $null
    }

    # 拷贝一份，必要时把推荐项插到首位
    $list = @()
    $defaultIndex = $null
    if ($preferred) {
        $list = , $preferred + @($Options | Where-Object { $_ -ne $preferred })
        $defaultIndex = 1
    }
    else {
        $list = @($Options)
    }

    Write-Host ''
    Write-Host "    $Title" -ForegroundColor Cyan
    for ($i = 0; $i -lt $list.Count; $i++) {
        $line = "      {0}) {1}" -f ($i + 1), $list[$i]
        if (($i + 1) -eq $defaultIndex) { $line += '    (推荐 / detected)' }
        Write-Host $line
    }
    Write-Host '      c) 自定义 / Custom...'
    Write-Host '      s) 跳过 / Skip (会渲染为 <未配置>)'

    $defaultLabel = if ($defaultIndex) { [string]$defaultIndex } else { 'c' }
    $choice = Read-Host "    选择 / Choose [$defaultLabel]"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $defaultLabel }
    # 去掉空白 / 控制字符 / BOM 等不可见字符（piped stdin 会出现）
    $choice = ($choice -replace '[\p{C}\p{Z}]', '').ToLowerInvariant()

    if ($choice -eq 's') { return $null }
    if ($choice -eq 'c') {
        $custom = Read-Host '    自定义命令 / Custom command'
        if ([string]::IsNullOrWhiteSpace($custom)) { return $preferred }
        return $custom.Trim()
    }
    if ($choice -match '^\d+$') {
        $idx = [int]$choice
        if ($idx -ge 1 -and $idx -le $list.Count) {
            return $list[$idx - 1]
        }
    }
    Write-Warning "无效选择 '$choice'，使用推荐值 / Invalid choice, falling back to recommended"
    return $preferred
}

$TestOptions = @(
    'dotnet test',
    'npm test',
    'pnpm test',
    'yarn test',
    'pytest',
    'cargo test',
    'go test ./...',
    'mvn test',
    'gradle test'
)
$LintOptions = @(
    'dotnet format --verify-no-changes',
    'npm run lint',
    'pnpm run lint',
    'eslint .',
    'ruff check .',
    'black --check .',
    'cargo clippy -- -D warnings',
    'gofmt -l . && go vet ./...',
    'mvn checkstyle:check'
)

$Unconfigured = '<未配置>'
$interactive = -not $NonInteractive

Write-Host ''
Write-Host "==> Harness Engineering v$HarnessVersion · 集成同步 / Integration sync" -ForegroundColor Cyan
Write-Host "    目标仓库 / Target repo : $TargetRepo"
Write-Host "    安装目标 / Targets     : $($Targets -join ', ')"
Write-Host "    交互模式 / Interactive : $(if ($NonInteractive) { '否 / no' } else { '是 / yes' })"

# 探测摘要（仅用于提示用户）
$detectedSummary = @()
foreach ($k in @('TestCommand', 'LintCommand')) {
    if ($detected[$k]) { $detectedSummary += "$k = $($detected[$k])" }
}
if ($detectedSummary) {
    Write-Host ''
    Write-Host '    自动探测 / Auto-detected:' -ForegroundColor DarkCyan
    foreach ($s in $detectedSummary) { Write-Host "      $s" -ForegroundColor DarkCyan }
}
if ($priorReplacements.Count -gt 0) {
    Write-Host ''
    Write-Host "    检测到上次 manifest（v$($priorManifest.harness_version)），将作为默认值预填 / Detected previous manifest, prefilling defaults" -ForegroundColor DarkCyan
}
Write-Host ''

$TestCommand = Resolve-CommandWithMenu -Cli $TestCommand -ManifestKey 'TEST_COMMAND' -Detected $detected.TestCommand -Title '测试命令 / Test command (TEST_COMMAND)'                  -Options $TestOptions -Interactive $interactive
$LintCommand = Resolve-CommandWithMenu -Cli $LintCommand -ManifestKey 'LINT_COMMAND' -Detected $detected.LintCommand -Title '代码风格检查命令 / Lint command (LINT_COMMAND)'         -Options $LintOptions -Interactive $interactive

# Vendor 目录：CLI 显式传入 > 上次 manifest.vendor_dir > 参数默认值（.he）；
# 未显式传入且交互模式 → 弹 prompt，回车采纳默认。
if (-not $NoVendor) {
    if (-not $PSBoundParameters.ContainsKey('VendorHarnessTo')) {
        $vendorDefault = $VendorHarnessTo
        if ($priorManifestVendorDir) { $vendorDefault = $priorManifestVendorDir }
        if ($interactive) {
            $hint = " [$vendorDefault]"
            $value = Read-Host "Vendor 目录 / Vendor directory (relative to TargetRepo)$hint"
            if ([string]::IsNullOrWhiteSpace($value)) { $VendorHarnessTo = $vendorDefault } else { $VendorHarnessTo = $value.Trim() }
        }
        else {
            $VendorHarnessTo = $vendorDefault
        }
    }
}

if ($NoVendor) {
    $defaultRef = if ($priorReplacements.ContainsKey('HARNESS_REPO_REF')) { [string]$priorReplacements['HARNESS_REPO_REF'] } else { 'https://github.com/shuaihuadu/harness-engineering' }
    $HarnessRepoRef = Resolve-Placeholder -Cli $HarnessRepoRef -ManifestKey 'HARNESS_REPO_REF' -Detected $defaultRef -Prompt '规范引用 / Harness repo ref (HARNESS_REPO_REF, path or URL)' -Interactive $interactive
    if (-not $HarnessRepoRef) { $HarnessRepoRef = $defaultRef }
    $VendorHarnessTo = $null
}
else {
    if (-not $HarnessRepoRef) { $HarnessRepoRef = $VendorHarnessTo }
}

# 可选字段留空 → 填 <未配置>
foreach ($v in @(@{ N = 'TestCommand'; R = [ref]$TestCommand }, @{ N = 'LintCommand'; R = [ref]$LintCommand })) {
    if ([string]::IsNullOrWhiteSpace($v.R.Value)) { $v.R.Value = $Unconfigured }
}
if ([string]::IsNullOrWhiteSpace($HarnessRepoRef)) {
    throw 'HARNESS_REPO_REF 不能为空'
}

$Replacements = [ordered]@{
    'TEST_COMMAND'                 = $TestCommand
    'LINT_COMMAND'                 = $LintCommand
    'HARNESS_REPO_REF'             = $HarnessRepoRef
    'HARNESS_VERSION'              = $HarnessVersion
    # 派生占位符：从 .github/ 子目录链接回 vendor 时需多一级 ../；URL 则保持原样
    'HARNESS_REPO_REF_FROM_GITHUB' = $(if ($HarnessRepoRef -match '^(https?://|/)') { $HarnessRepoRef } else { "../$HarnessRepoRef" })
    # VENDOR_DIR：被 vendor 文档与 .github/ 模板引用 vendor 目录时使用；NoVendor 模式下退回 .he 占位
    'VENDOR_DIR'                   = $(if ($VendorHarnessTo) { $VendorHarnessTo } else { '.he' })
}

# 4) 总结 + 确认
Write-Host ''
Write-Host '==> 即将使用以下占位符渲染 / Rendering with placeholders:' -ForegroundColor Cyan
foreach ($k in $Replacements.Keys) {
    $val = $Replacements[$k]
    $color = if ($val -eq $Unconfigured) { 'Yellow' } else { 'Gray' }
    Write-Host ("    {0,-20} = {1}" -f $k, $val) -ForegroundColor $color
}
$unconfiguredCount = @($Replacements.Values | Where-Object { $_ -eq $Unconfigured }).Count
if ($unconfiguredCount -gt 0) {
    Write-Host ''
    Write-Host "    [!] 有 $unconfiguredCount 项未配置，将渲染为 `<未配置>` / $unconfiguredCount placeholder(s) unset, will render as `<未配置>`. To find them later:" -ForegroundColor Yellow
    Write-Host "        Get-ChildItem '$TargetRepo/.github' -Recurse -File | Select-String '<未配置>'" -ForegroundColor Yellow
}

if ($interactive) {
    Write-Host ''
    $confirm = Read-Host '继续？/ Proceed? [Y/n]'
    if ($confirm -and $confirm.Trim().ToLowerInvariant() -in @('n', 'no')) {
        Write-Host '已取消 / Cancelled.' -ForegroundColor DarkYellow
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
    HarnessRoot    = $RepoRoot
    Manifest       = [System.Collections.Generic.List[hashtable]]::new()
}

# Selections：target 名 → 用户挑的 stem 列表（含 'all'）
$Selections = @{}
if ($CopilotAgents) {
    $Selections['copilot/custom-agents'] = $CopilotAgents
}

# ----------------------------------------------------------------------------
# 1. 执行 target（target.json 里的 directory/single/tree render 自行处理 vendor 投放）
# ----------------------------------------------------------------------------
foreach ($t in $validTargets) {
    Invoke-Target -Context $Context -TargetDir $t.Dir -TargetRepoRoot $TargetRepo -Selections $Selections
}

# ----------------------------------------------------------------------------
# 3. 写 manifest（uninstall 依赖此文件）
# ----------------------------------------------------------------------------
# manifest 永远落 vendor 目录；NoVendor 模式下退回 .he/（仅放 manifest，不放文档）
$manifestVendorDir = if ($VendorHarnessTo) { $VendorHarnessTo } else { '.he' }
$manifestDir = Join-Path $TargetRepo $manifestVendorDir
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
    Write-Host "==> 已写入 manifest / Manifest written: $manifestPath" -ForegroundColor Cyan

    # ----------------------------------------------------------------------------
    # install.log（每次 install / uninstall 追加一行，作为变更审计来源）
    # ----------------------------------------------------------------------------
    $renderedCount = @($Context.Manifest | Where-Object { $_.kind -eq 'rendered' }).Count
    $vendoredCount = @($Context.Manifest | Where-Object { $_.kind -eq 'vendored' }).Count
    $totalCount = @($Context.Manifest).Count
    $logPath = Join-Path $manifestDir 'install.log'
    $tsIso = (Get-Date).ToString('o')
    $commitTag = if ($harnessCommit) { $harnessCommit } else { 'unknown' }
    $targetsTag = ($Targets -join ',')
    $logLine = "[$tsIso] install · harness@$commitTag · targets=$targetsTag · files=$totalCount (rendered=$renderedCount, vendored=$vendoredCount)`n"
    [System.IO.File]::AppendAllText($logPath, $logLine, [System.Text.UTF8Encoding]::new($false))
}

# ----------------------------------------------------------------------------
# 完成提示
# ----------------------------------------------------------------------------
Write-Host ''
if ($DryRun) {
    Write-Host 'DryRun 完成，未写入任何文件 / DryRun done, nothing written.' -ForegroundColor Cyan
}
else {
    $githubCount = @($Context.Manifest | Where-Object { $_.path -like '.github/*' }).Count
    $harnessCount = @($Context.Manifest | Where-Object { $_.path -like "$manifestVendorDir/*" }).Count

    Write-Host '==> 安装完成 / Install complete' -ForegroundColor Green
    Write-Host ("    [+] 写入 {0} 个文件到 .github/                  Copilot 开箱即用" -f $githubCount)
    Write-Host ("    [+] 写入 {0} 个文件到 $manifestVendorDir/    HANDBOOK + docs + manifest" -f $harnessCount)
    Write-Host ''
    Write-Host '下一步 / Next steps:' -ForegroundColor Cyan
    Write-Host '   1. 读 10 分钟操作手册 / Read the 10-min handbook:'
    Write-Host "        notepad .\$manifestVendorDir\HANDBOOK.md"
    Write-Host '   2. 跑一遍空跑演练 / Run a dry-run rehearsal (强烈推荐 / strongly recommended):'
    Write-Host '        New-Item -ItemType Directory -Path .\docs\00-dry-run -Force | Out-Null'
    Write-Host '        Copy-Item .\.github\templates\dry-run-demo.md .\docs\00-dry-run\'
    Write-Host '        然后按文档清单走一遍 H1->H6，30~60 分钟'
    Write-Host '        目的: 在拿真实需求前发现 Harness 在你项目里的不适配点，比真实需求踩坑便宜得多'
    Write-Host '   3. 起一个最小任务试手 / Try a smallest task:'
    Write-Host '        在 Copilot Chat 输入 / In Copilot Chat type:  /new-task'
    Write-Host '        (首次运行会按模板自动建 docs\06-tasks\task-board.md，无需手动复制)'
    Write-Host '   4. 可选 / Optional: 把 vendor 目录加入 .gitignore'
    Write-Host "        说明见 / See:  .\$manifestVendorDir\README.md"
    Write-Host ''
    Write-Host '卸载 / Uninstall:' -ForegroundColor DarkGray
    Write-Host '   pwsh -File .\.he\uninstall.ps1'
}
Write-Host ''
