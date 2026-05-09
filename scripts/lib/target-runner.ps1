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
              "kind": "directory",                 // 目录批量（平铺，只看顶层文件）
              "source_dir": "instructions",
              "target_dir": ".github/instructions",
              "source_glob": "*.instructions.template.md",
              "target_glob": "*.instructions.md",
              "selectable": false,                 // 是否允许用户挑子集
              "select_param": null,                // CLI 选择参数名（仅 selectable=true 有意义）
              "default_select": [],                // 默认安装的 stem 列表
              "orphan_check": true,                // 是否做孤儿检测
              "orphan_check_only_when_all": false  // 仅 'all' 时检测（避免误删用户主动不装的项）
            },
            {
              "kind": "tree",                      // 树形复制：递归拷贝 source_dir 下每个一级子目录中的全部文件
              "source_dir": "../_skills",          //   顶层文件（如 _skills/README.md）被视为框架文档不拷入目标
              "target_dir": ".github/skills",      //   供 GitHub Copilot Skills 机制发现（.github/skills/<name>/SKILL.md）
              "orphan_check": true                 //   同 directory：源删除 → 目标检出后提示 / 删除
            }
          ]
        }
#>

Set-StrictMode -Version Latest

# ----------------------------------------------------------------------------
# 在 target.json 的 target 路径上展开 {{KEY}} 占位符（支持 VENDOR_DIR 等）
# Replace {{KEY}} placeholders inside JSON-declared target paths.
# ----------------------------------------------------------------------------
function Expand-TargetPlaceholders {
    param(
        [Parameter(Mandatory)] [hashtable] $Replacements,
        [AllowEmptyString()] [string] $Value
    )
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    $out = $Value
    foreach ($key in $Replacements.Keys) {
        $token = '{{' + $key + '}}'
        $out = $out.Replace($token, [string]$Replacements[$key])
    }
    return $out
}

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
            'tree' {
                Invoke-RenderTree -Context $Context -Spec $render -TargetDir $TargetDir -TargetRepoRoot $TargetRepoRoot
            }
            default {
                throw "不支持的 render kind：$kind（in $($spec.name)）"
            }
        }
    }
}

function Read-SelectableMenu {
    <#
    .SYNOPSIS
        交互式菜单：从 SourceDir 中列出可选模板让用户挑选。
        Interactive menu: list selectable templates and let user pick.

    .DESCRIPTION
        - 列出目录中所有匹配 SourceGlob 的模板，去掉 .template 后缀作为 stem 展示
        - 默认值由 DefaultSelect 决定：空数组 → 默认 none；含 'all' → 默认 all；否则按 stem 列预选
        - 用户输入支持：编号（1,3）/ stem 名（commit-auditor,design-reviewer）/ 'all' / 'none' / 空回车采纳默认
        - 返回值：'all' / 空数组 / 选中的 stem 数组
    #>
    param(
        [Parameter(Mandatory)] [string]   $SourceDir,
        [Parameter(Mandatory)] [string]   $SourceGlob,
        [AllowEmptyCollection()] [string[]] $DefaultSelect = @(),
        [Parameter(Mandatory)] [string]   $GroupName
    )

    $items = Get-ChildItem -Path $SourceDir -Filter $SourceGlob | Sort-Object Name
    if (@($items).Count -eq 0) { return @() }

    # 计算默认提示
    $defaultLabel = if ($DefaultSelect -contains 'all') { 'all' }
    elseif (@($DefaultSelect).Count -eq 0) { 'none' }
    else { ($DefaultSelect -join ',') }

    Write-Host ''
    Write-Host "   ?  $GroupName 可选项 / available items:" -ForegroundColor Cyan
    $i = 0
    $stems = @()
    foreach ($f in $items) {
        $i++
        # 渲染器把第一段 `.` 之前作为 stem（与 Where-Object { -like "$stem.*" } 的语义一致）
        # the renderer treats the first dot-segment as the stem
        $stem = ($f.Name -replace '\.template', '') -split '\.' | Select-Object -First 1
        $stems += $stem
        Write-Host ("        [{0}] {1}" -f $i, $stem)
    }
    Write-Host '      输入编号（1,3）/ stem 名 / all / none，回车采纳默认' -ForegroundColor DarkGray
    Write-Host '      Enter numbers (e.g. 1,3) / stem names / all / none; press Enter for default' -ForegroundColor DarkGray
    $answer = Read-Host "      选择 / Choose [$defaultLabel]"

    if ([string]::IsNullOrWhiteSpace($answer)) {
        # 采纳默认
        return $DefaultSelect
    }
    $answer = $answer.Trim().ToLowerInvariant()
    if ($answer -eq 'all') { return @('all') }
    if ($answer -in @('none', 'no', 'n', '0', '-', 'skip')) { return @() }

    # 解析编号 / stem 混合
    $parts = $answer -split '[,\s]+' | Where-Object { $_ }
    $picked = New-Object System.Collections.Generic.List[string]
    foreach ($p in $parts) {
        if ($p -match '^\d+$') {
            $idx = [int]$p
            if ($idx -ge 1 -and $idx -le $stems.Count) { [void]$picked.Add($stems[$idx - 1]) }
            else { Write-Warning "无效编号 / invalid index: $p" }
        }
        else {
            if ($stems -contains $p) { [void]$picked.Add($p) }
            else { Write-Warning "未找到模板 / unknown stem: $p" }
        }
    }
    return @($picked | Select-Object -Unique)
}

function Invoke-RenderSingle {
    param([hashtable]$Context, [object]$Spec, [string]$TargetDir, [string]$TargetRepoRoot)

    $src = Join-Path $TargetDir $Spec.source
    $targetRel = Expand-TargetPlaceholders -Replacements $Context.Replacements -Value $Spec.target
    $dst = Join-Path $TargetRepoRoot $targetRel
    if (-not (Test-Path $src)) { throw "source 不存在：$src" }
    Sync-RenderedFile -Context $Context -Source $src -Destination $dst
}

function Invoke-RenderDirectory {
    param([hashtable]$Context, [object]$Spec, [string]$TargetDir, [string]$TargetRepoRoot, [hashtable]$Selections, [string]$TargetName)

    $srcDir = Join-Path $TargetDir $Spec.source_dir
    $targetSubdir = Expand-TargetPlaceholders -Replacements $Context.Replacements -Value $Spec.target_dir
    $dstDir = Join-Path $TargetRepoRoot $targetSubdir
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
        # 优先级：用户为该目录指定的选择 > target 下默认 > 交互菜单（仅交互模式） > target.json 的 default_select
        # priority: per-directory selection > per-target selection > interactive menu (only when interactive) > default_select
        $key = "$TargetName/$($Spec.source_dir)"
        $picked = $null
        $hasUserChoice = $false
        if ($Selections.ContainsKey($key)) { $picked = $Selections[$key]; $hasUserChoice = $true }
        elseif ($Selections.ContainsKey($TargetName)) { $picked = $Selections[$TargetName]; $hasUserChoice = $true }

        if (-not $hasUserChoice) {
            $isInteractive = -not $Context.NonInteractive
            if ($isInteractive) {
                # 交互菜单：列出所有可选模板让用户挑（默认值取自 default_select）
                # interactive menu: list all available templates and let the user pick
                $defaultSelect = @()
                if ($Spec.PSObject.Properties.Name -contains 'default_select') {
                    $defaultSelect = @($Spec.default_select)
                }
                $picked = Read-SelectableMenu -SourceDir $srcDir -SourceGlob $srcGlob -DefaultSelect $defaultSelect -GroupName $Spec.source_dir
                $hasUserChoice = $true
            }
            else {
                # 非交互：完全交给 default_select
                # default_select 缺失 ⇒ 装全部；default_select=[] ⇒ 一个都不装
                if ($Spec.PSObject.Properties.Name -contains 'default_select') {
                    $picked = @($Spec.default_select)
                }
                else {
                    $picked = @('all')
                }
            }
        }

        if (@($picked).Count -eq 0) {
            Write-Host "   skip   $($Spec.source_dir)：未选择任何项 / nothing selected" -ForegroundColor DarkGray
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

function Invoke-RenderTree {
    <#
    .SYNOPSIS
        树形复制：递归拷贝 source_dir 下每个一级子目录中的全部文件到 target_dir 对应路径。
        顶层文件（如 README.md）不拷入目标，只拷 "一个子目录 = 一个业务单位" 这种结构化产物。
        主要服务于 GitHub Copilot Skills（.github/skills/<name>/SKILL.md）这类需要保留一层名字子目录的场景。
    #>
    param([hashtable]$Context, [object]$Spec, [string]$TargetDir, [string]$TargetRepoRoot)

    $srcDir = Join-Path $TargetDir $Spec.source_dir
    $targetSubdir = Expand-TargetPlaceholders -Replacements $Context.Replacements -Value $Spec.target_dir
    $dstDir = Join-Path $TargetRepoRoot $targetSubdir

    if (-not (Test-Path $srcDir)) {
        Write-Host "   skip   $srcDir 不存在" -ForegroundColor DarkGray
        return
    }
    $srcDirAbs = (Resolve-Path -LiteralPath $srcDir).Path

    $expectedRel = New-Object System.Collections.Generic.List[string]
    $subdirs = @(Get-ChildItem -LiteralPath $srcDirAbs -Directory)
    foreach ($sub in $subdirs) {
        Get-ChildItem -LiteralPath $sub.FullName -Recurse -File | ForEach-Object {
            $rel = Get-RelativePathInternal -Base $srcDirAbs -Path $_.FullName
            $dst = Join-Path $dstDir $rel
            Sync-RenderedFile -Context $Context -Source $_.FullName -Destination $dst
            [void]$expectedRel.Add($rel.Replace('\', '/'))
        }
    }

    $orphanCheck = $false
    if ($Spec.PSObject.Properties.Name -contains 'orphan_check') { $orphanCheck = [bool]$Spec.orphan_check }
    if ($orphanCheck) {
        Sync-TreeOrphans -Context $Context -DestinationDir $dstDir -ExpectedRelPaths $expectedRel
    }
}
