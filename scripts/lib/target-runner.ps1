<#
.SYNOPSIS
    Harness Engineering · Target 调度器（读取 target.json 并按声明执行渲染）。

.DESCRIPTION
    每个集成 target（copilot / claude-code / codex / ...）下都有一份 target.json，
    描述该工具需要把哪些模板渲染成哪些文件。本调度器是 target-agnostic 的，
    只认 JSON 声明，便于未来快速扩展新 target。

    target.json schema（v1）:
        {
          "name": "copilot",                       // 标识，必填
          "display": "GitHub Copilot",             // 展示名，必填
          "renders": [
            {
              "kind": "single",                    // 单文件
              "source": "copilot-instructions.template.md",
              "target": ".github/copilot-instructions.md"
            },
            {
              "kind": "directory",                 // 目录批量
              "source_dir": "instructions",
              "target_dir": ".github/instructions",
              "source_glob": "*.instructions.template.md",
              "target_glob": "*.instructions.md",
              "selectable": false,                 // 是否允许用户挑子集
              "select_param": null,                // CLI 选择参数名（仅 selectable=true 有意义）
              "default_select": [],                // 默认安装的 stem 列表
              "orphan_check": true,                // 是否做孤儿检测
              "orphan_check_only_when_all": false  // 仅 'all' 时检测（避免误删用户主动不装的项）
            }
          ]
        }
#>

Set-StrictMode -Version Latest

# ----------------------------------------------------------------------------
# 加载 target.json
# ----------------------------------------------------------------------------
function Read-TargetSpec {
    param([Parameter(Mandatory)] [string] $TargetDir)

    $jsonPath = Join-Path $TargetDir 'target.json'
    if (-not (Test-Path $jsonPath)) {
        throw "未找到 target 清单：$jsonPath"
    }

    $raw = [System.IO.File]::ReadAllText($jsonPath, [System.Text.UTF8Encoding]::new($false))
    $spec = $raw | ConvertFrom-Json
    if (-not $spec.name) { throw "target.json 缺少 name 字段：$jsonPath" }
    if (-not $spec.renders) { throw "target.json 缺少 renders 字段：$jsonPath" }
    return $spec
}

# ----------------------------------------------------------------------------
# 执行单个 target
# ----------------------------------------------------------------------------
function Invoke-Target {
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [Parameter(Mandatory)] [string]    $TargetDir,        # 模板源目录（绝对路径）
        [Parameter(Mandatory)] [string]    $TargetRepoRoot,   # 采用方仓库根（绝对路径）
        [Parameter(Mandatory)] [hashtable] $Selections        # target 名 -> 用户选择数组（包含 'all' 或 stem 列表）
    )

    $spec = Read-TargetSpec -TargetDir $TargetDir

    Write-Host ''
    Write-Host "==> [$($spec.display)] 开始同步" -ForegroundColor Cyan

    $stepIdx = 0
    $stepTotal = @($spec.renders).Count

    foreach ($render in $spec.renders) {
        $stepIdx++
        $kind = "$($render.kind)"
        Write-Host ''
        Write-Host "[$stepIdx/$stepTotal · $($spec.name) · $kind]" -ForegroundColor Cyan

        switch ($kind) {
            'single' {
                Invoke-RenderSingle -Context $Context -Spec $render -TargetDir $TargetDir -TargetRepoRoot $TargetRepoRoot
            }
            'directory' {
                Invoke-RenderDirectory -Context $Context -Spec $render -TargetDir $TargetDir -TargetRepoRoot $TargetRepoRoot -Selections $Selections -TargetName $spec.name
            }
            default {
                throw "不支持的 render kind：$kind（in $($spec.name)）"
            }
        }
    }
}

function Invoke-RenderSingle {
    param([hashtable]$Context, [object]$Spec, [string]$TargetDir, [string]$TargetRepoRoot)

    $src = Join-Path $TargetDir $Spec.source
    $dst = Join-Path $TargetRepoRoot $Spec.target
    if (-not (Test-Path $src)) { throw "source 不存在：$src" }
    Sync-RenderedFile -Context $Context -Source $src -Destination $dst
}

function Invoke-RenderDirectory {
    param([hashtable]$Context, [object]$Spec, [string]$TargetDir, [string]$TargetRepoRoot, [hashtable]$Selections, [string]$TargetName)

    $srcDir = Join-Path $TargetDir $Spec.source_dir
    $dstDir = Join-Path $TargetRepoRoot $Spec.target_dir
    $srcGlob = $Spec.source_glob
    $tgtGlob = $Spec.target_glob

    if (-not (Test-Path $srcDir)) {
        Write-Host "   skip   $srcDir 不存在" -ForegroundColor DarkGray
        return
    }

    # 1. 选择要渲染的文件
    $selectable = $false
    if ($Spec.PSObject.Properties.Name -contains 'selectable') { $selectable = [bool]$Spec.selectable }
    $useAll = $false
    $selectedStems = @()

    if ($selectable) {
        # 优先级：用户为该目录指定的选择 > target 下默认 > target.json 的 default_select > 全部
        $key = "$TargetName/$($Spec.source_dir)"
        $picked = $null
        $hasUserChoice = $false
        if ($Selections.ContainsKey($key)) { $picked = $Selections[$key]; $hasUserChoice = $true }
        elseif ($Selections.ContainsKey($TargetName)) { $picked = $Selections[$TargetName]; $hasUserChoice = $true }

        if (-not $hasUserChoice) {
            # 用户未传选择 → 完全交给 target.json 的 default_select 决定
            # default_select 缺失 ⇒ 装全部；default_select=[] ⇒ 一个都不装
            if ($Spec.PSObject.Properties.Name -contains 'default_select') {
                $picked = @($Spec.default_select)
            }
            else {
                $picked = @('all')
            }
        }

        if (@($picked).Count -eq 0) {
            Write-Host "   skip   $($Spec.source_dir)：未选择任何项（target.json 默认空集，且未指定 -Chatmodes/选择参数）" -ForegroundColor DarkGray
            return
        }

        if ($picked -contains 'all') { $useAll = $true } else { $selectedStems = @($picked) }
    }
    else {
        $useAll = $true
    }

    # 2. 渲染
    $allTemplates = Get-ChildItem -Path $srcDir -Filter $srcGlob
    $filesToRender = if ($useAll) {
        $allTemplates
    }
    else {
        $selectedStems | ForEach-Object {
            $stem = $_
            $candidate = $allTemplates | Where-Object { ($_.Name -replace '\.template', '') -like "$stem.*" }
            if (-not $candidate) {
                Write-Warning "未找到模板 $stem（in $srcDir）"
                return
            }
            $candidate
        } | Where-Object { $_ }
    }

    foreach ($file in $filesToRender) {
        $destName = $file.Name -replace '\.template', ''
        Sync-RenderedFile -Context $Context -Source $file.FullName -Destination (Join-Path $dstDir $destName)
    }

    # 3. 孤儿检测
    $orphanCheck = $false
    if ($Spec.PSObject.Properties.Name -contains 'orphan_check') { $orphanCheck = [bool]$Spec.orphan_check }
    $orphanOnAll = $false
    if ($Spec.PSObject.Properties.Name -contains 'orphan_check_only_when_all') { $orphanOnAll = [bool]$Spec.orphan_check_only_when_all }

    if ($orphanCheck -and (-not $orphanOnAll -or $useAll)) {
        Sync-RenderOrphans -Context $Context -SourceDir $srcDir -DestinationDir $dstDir -SourceGlob $srcGlob -TargetGlob $tgtGlob
    }
}
