<#
.SYNOPSIS
    Harness Engineering · 通用同步引擎（target-agnostic）。

.DESCRIPTION
    本文件提供 render / vendor / conflict / orphan 的通用 IO 与决策函数，
    所有跨调用的状态都收敛到 [hashtable] $Context 参数，避免脚本作用域污染。

    所有函数均设计为：
    - 幂等（字节级比较，无变化时静默跳过）
    - 中性（不知道 target 是谁，不依赖任何业务文件名）
    - 跨平台（仅依赖 .NET BCL，不调用平台命令）

    Context 字段约定：
        Force          [bool]   全自动覆盖 + 自动删除孤儿
        NoDelete       [bool]   一律不删除孤儿
        DryRun         [bool]   只打印不写盘
        OverwriteAll   [bool]   会话级"全部覆盖"开关，由引擎自管理
        DeleteAll      [bool]   会话级"全部删除"开关，由引擎自管理
        Replacements   [hashtable]  占位符键值对（不带 {{}}）
        TargetRepo     [string]  采用方仓库根（用于 manifest 中相对路径计算）
        Manifest       [List]    每个 entry：@{ path; sha256; kind }；引擎在写入/同步/skip 时追加
#>

Set-StrictMode -Version Latest

# ============================================================================
# INCLUDE 指令展开
# ============================================================================
# 支持两种形式：
#   {{INCLUDE: <path>}}       原样 inline 整个文件
#   {{INCLUDE_BODY: <path>}}  inline 时去掉 YAML frontmatter 和首个 H1 标题行
#
# path 是相对于 harness 仓库根（HarnessRoot）的路径，例如 'agents/repo-impact-mapper/AGENT.md'。
#
# inline 完成后会对内嵌 markdown 链接做"安全降级"：
# 跨文件相对链接（指向 _shared/、docs/、根 README.md、同目录 AGENT.md 这些 inline 后必然失效的目标）
# 一律剥成纯文本，避免 .github/ 下出现链向不存在路径的 broken link。
function Expand-Includes {
    param(
        [Parameter(Mandatory)] [string] $Content,
        [Parameter(Mandatory)] [string] $HarnessRoot
    )

    $regex = [regex]'\{\{INCLUDE(_BODY)?:\s*([^\}]+)\}\}'
    $maxIter = 16
    $iter = 0
    while ($regex.IsMatch($Content)) {
        $iter++
        if ($iter -gt $maxIter) {
            throw "INCLUDE 嵌套深度超过 $maxIter 层，疑似循环引用"
        }
        $Content = $regex.Replace($Content, {
                param($m)
                $stripBody = $m.Groups[1].Value -eq '_BODY'
                $relPath = $m.Groups[2].Value.Trim()
                $absPath = Join-Path $HarnessRoot $relPath
                if (-not (Test-Path -LiteralPath $absPath -PathType Leaf)) {
                    throw "INCLUDE 引用的源文件不存在：$absPath"
                }
                $body = [System.IO.File]::ReadAllText($absPath, [System.Text.UTF8Encoding]::new($false))

                if ($stripBody) {
                    # 去掉 YAML frontmatter
                    $body = [regex]::Replace($body, '^---\r?\n[\s\S]*?\r?\n---\r?\n', '')
                    # 去掉首个 H1 行
                    $body = [regex]::Replace($body, '^\s*#\s+[^\r\n]*\r?\n', '')
                }

                # 安全降级：剥掉指向 inline 后必然失效的跨文件链接外壳，保留文字
                $body = [regex]::Replace($body, '\[([^\]]+)\]\(\.\.\/_shared\/[^\)]+\)', '$1')
                $body = [regex]::Replace($body, '\[([^\]]+)\]\(\.\.\/\.\.\/docs\/[^\)]+\)', '$1')
                $body = [regex]::Replace($body, '\[([^\]]+)\]\(\.\.\/\.\.\/README\.md[^\)]*\)', '$1')
                $body = [regex]::Replace($body, '\[([^\]]+)\]\(AGENT\.md[^\)]*\)', '$1')

                return $body
            })
    }
    return $Content
}

# ============================================================================
# 占位符渲染
# ============================================================================
function Invoke-Placeholders {
    param(
        [Parameter(Mandatory)] [string] $Content,
        [Parameter(Mandatory)] [hashtable] $Replacements
    )
    foreach ($key in $Replacements.Keys) {
        $Content = $Content.Replace('{{' + $key + '}}', [string]$Replacements[$key])
    }
    return $Content
}

# ============================================================================
# 字节级 IO
# ============================================================================
function Get-FileBytesInternal {
    param([string]$Path)
    return [System.IO.File]::ReadAllBytes($Path)
}

function Test-BytesEqualInternal {
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
    return $true
}

function Write-FileUtf8NoBomInternal {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-FileBytesInternal {
    param([string]$Path, [byte[]]$Bytes)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

# ============================================================================
# Manifest 追踪
# ============================================================================
function Get-Sha256HexInternal {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Add-ManifestEntryInternal {
    param([hashtable]$Context, [string]$AbsPath, [byte[]]$CanonicalBytes, [string]$Kind)
    if (-not $Context.ContainsKey('Manifest') -or $null -eq $Context.Manifest) { return }
    if (-not $Context.ContainsKey('TargetRepo') -or [string]::IsNullOrWhiteSpace($Context.TargetRepo)) { return }
    $rel = [System.IO.Path]::GetRelativePath($Context.TargetRepo, $AbsPath).Replace('\', '/')
    $Context.Manifest.Add(@{
            path   = $rel
            sha256 = (Get-Sha256HexInternal -Bytes $CanonicalBytes)
            kind   = $Kind
        }) | Out-Null
}

# ============================================================================
# 交互决策（内部）
# ============================================================================
function Resolve-ConflictDecisionInternal {
    param([hashtable]$Context, [string]$Path, [string]$Kind)
    if ($Context.Force) { return 'overwrite' }
    if ($Context.OverwriteAll) { return 'overwrite' }
    if ($Context.NonInteractive) { return 'keep' }

    Write-Host ''
    Write-Host "  ! 冲突：$Kind 内容与现有文件不一致" -ForegroundColor Yellow
    Write-Host "    $Path"
    while ($true) {
        $raw = Read-Host '    [O]verwrite / [K]eep / [A]ll-overwrite / a[B]ort'
        if ($null -eq $raw) { throw '输入流已结束，无法获取冲突决定（非交互模式请使用 -Force 或 -DryRun）' }
        switch ($raw.Trim().ToLowerInvariant()) {
            'o' { return 'overwrite' }
            'k' { return 'keep' }
            'a' { $Context.OverwriteAll = $true; return 'overwrite' }
            'b' { return 'abort' }
            default { Write-Host '    请输入 O / K / A / B' -ForegroundColor DarkYellow }
        }
    }
}

function Resolve-DeleteDecisionInternal {
    param([hashtable]$Context, [string]$Path)
    if ($Context.NoDelete) { return 'keep' }
    if ($Context.Force) { return 'delete' }
    if ($Context.DeleteAll) { return 'delete' }
    if ($Context.NonInteractive) { return 'keep' }

    Write-Host ''
    Write-Host '  ! 孤儿：源已删除，但目标仍存在' -ForegroundColor Yellow
    Write-Host "    $Path"
    while ($true) {
        $raw = Read-Host '    [D]elete / [K]eep / [A]ll-delete / a[B]ort'
        if ($null -eq $raw) { throw '输入流已结束，无法获取删除决定（非交互模式请使用 -NoDelete 或 -Force）' }
        switch ($raw.Trim().ToLowerInvariant()) {
            'd' { return 'delete' }
            'k' { return 'keep' }
            'a' { $Context.DeleteAll = $true; return 'delete' }
            'b' { return 'abort' }
            default { Write-Host '    请输入 D / K / A / B' -ForegroundColor DarkYellow }
        }
    }
}

# ============================================================================
# 公开 API
# ============================================================================

# 同步单个被渲染的模板文件
function Sync-RenderedFile {
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [Parameter(Mandatory)] [string]    $Source,
        [Parameter(Mandatory)] [string]    $Destination
    )

    $rawText = [System.IO.File]::ReadAllText($Source, [System.Text.UTF8Encoding]::new($false))

    # 先展开 INCLUDE 指令（如有），再做占位符替换
    if ($Context.Contains('HarnessRoot') -and $Context.HarnessRoot) {
        $rawText = Expand-Includes -Content $rawText -HarnessRoot $Context.HarnessRoot
    }

    # 按目标文件深度动态计算 HARNESS_REPO_REF_FROM_GITHUB：
    # 链接 target 写在 .github/copilot-instructions.md 时需 ../，
    # 写在 .github/agents/foo.agent.md 时需 ../../，URL 则保持原样。
    $perFileReplacements = @{}
    foreach ($k in $Context.Replacements.Keys) { $perFileReplacements[$k] = $Context.Replacements[$k] }
    if ($Context.Replacements.Contains('HARNESS_REPO_REF')) {
        $ref = [string]$Context.Replacements['HARNESS_REPO_REF']
        if ($ref -match '^(https?://|/)') {
            $perFileReplacements['HARNESS_REPO_REF_FROM_GITHUB'] = $ref
        }
        else {
            $destDir = Split-Path -Parent $Destination
            $relDir = [System.IO.Path]::GetRelativePath($Context.TargetRepo, $destDir)
            $depth = if ([string]::IsNullOrWhiteSpace($relDir) -or $relDir -eq '.') { 0 } else { ($relDir -split '[\\/]+').Count }
            $prefix = ('../' * $depth)
            $perFileReplacements['HARNESS_REPO_REF_FROM_GITHUB'] = "$prefix$ref"
        }
    }

    $newContent = Invoke-Placeholders -Content $rawText -Replacements $perFileReplacements
    $newBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($newContent)

    if (Test-Path $Destination) {
        $oldBytes = Get-FileBytesInternal $Destination
        if (Test-BytesEqualInternal $oldBytes $newBytes) {
            Write-Host "   skip   $Destination (unchanged)" -ForegroundColor DarkGray
            Add-ManifestEntryInternal -Context $Context -AbsPath $Destination -CanonicalBytes $newBytes -Kind 'rendered'
            return
        }
        $decision = Resolve-ConflictDecisionInternal -Context $Context -Path $Destination -Kind 'render'
        switch ($decision) {
            'keep' {
                Write-Host "   keep   $Destination" -ForegroundColor DarkYellow
                Add-ManifestEntryInternal -Context $Context -AbsPath $Destination -CanonicalBytes $newBytes -Kind 'rendered'
                return
            }
            'abort' { throw '用户中止' }
        }
    }

    if ($Context.DryRun) {
        Write-Host "   dryrun $Destination" -ForegroundColor DarkGray
    }
    else {
        Write-FileUtf8NoBomInternal -Path $Destination -Content $newContent
        Write-Host "   write  $Destination" -ForegroundColor Green
    }
    Add-ManifestEntryInternal -Context $Context -AbsPath $Destination -CanonicalBytes $newBytes -Kind 'rendered'
}

# 同步整棵 vendor 目录（递归 + 删除孤儿）
function Sync-VendoredTree {
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [Parameter(Mandatory)] [string]    $SourceRoot,
        [Parameter(Mandatory)] [string]    $TargetRoot,
        [Parameter(Mandatory)] [string[]]  $Items
    )

    $sourceFiles = @{}
    foreach ($item in $Items) {
        $itemPath = Join-Path $SourceRoot $item
        if (-not (Test-Path $itemPath)) { continue }
        if (Test-Path $itemPath -PathType Leaf) {
            $sourceFiles[$item] = $itemPath
        }
        else {
            Get-ChildItem -Path $itemPath -Recurse -File | Where-Object {
                # 排除 sync-engine 的输入产物（仅供渲染，不应进 vendor）
                $_.Name -notlike '*.template.md' -and $_.Name -notlike '*.md.template' -and $_.Name -ne 'target.json'
            } | ForEach-Object {
                $rel = [System.IO.Path]::GetRelativePath($SourceRoot, $_.FullName).Replace('\', '/')
                $sourceFiles[$rel] = $_.FullName
            }
        }
    }

    $targetFiles = @{}
    foreach ($item in $Items) {
        $itemPath = Join-Path $TargetRoot $item
        if (-not (Test-Path $itemPath)) { continue }
        if (Test-Path $itemPath -PathType Leaf) {
            $targetFiles[$item] = $itemPath
        }
        else {
            Get-ChildItem -Path $itemPath -Recurse -File | ForEach-Object {
                $rel = [System.IO.Path]::GetRelativePath($TargetRoot, $_.FullName).Replace('\', '/')
                $targetFiles[$rel] = $_.FullName
            }
        }
    }

    $orphans = @()
    foreach ($rel in $targetFiles.Keys) {
        if (-not $sourceFiles.ContainsKey($rel)) { $orphans += $rel }
    }

    Write-Host "   分类：源 $($sourceFiles.Count) 个文件 / 目标 $($targetFiles.Count) 个文件 / 孤儿 $($orphans.Count) 个" -ForegroundColor DarkCyan

    foreach ($rel in ($sourceFiles.Keys | Sort-Object)) {
        $src = $sourceFiles[$rel]
        $dst = Join-Path $TargetRoot $rel
        $newBytes = Get-FileBytesInternal $src

        if (Test-Path $dst) {
            $oldBytes = Get-FileBytesInternal $dst
            if (Test-BytesEqualInternal $oldBytes $newBytes) {
                Add-ManifestEntryInternal -Context $Context -AbsPath $dst -CanonicalBytes $newBytes -Kind 'vendored'
                continue
            }
            $decision = Resolve-ConflictDecisionInternal -Context $Context -Path $dst -Kind 'vendor'
            switch ($decision) {
                'keep' {
                    Write-Host "   keep   $dst" -ForegroundColor DarkYellow
                    Add-ManifestEntryInternal -Context $Context -AbsPath $dst -CanonicalBytes $newBytes -Kind 'vendored'
                    continue
                }
                'abort' { throw '用户中止' }
            }
        }

        if ($Context.DryRun) {
            Write-Host "   dryrun $dst" -ForegroundColor DarkGray
        }
        else {
            Write-FileBytesInternal -Path $dst -Bytes $newBytes
            Write-Host "   sync   $dst" -ForegroundColor Green
        }
        Add-ManifestEntryInternal -Context $Context -AbsPath $dst -CanonicalBytes $newBytes -Kind 'vendored'
    }

    foreach ($rel in ($orphans | Sort-Object)) {
        $dst = $targetFiles[$rel]
        $decision = Resolve-DeleteDecisionInternal -Context $Context -Path $dst
        switch ($decision) {
            'keep' { Write-Host "   keep   $dst (orphan)" -ForegroundColor DarkYellow; continue }
            'abort' { throw '用户中止' }
            'delete' {
                if ($Context.DryRun) {
                    Write-Host "   dryrun-delete $dst" -ForegroundColor DarkGray
                }
                else {
                    Remove-Item -LiteralPath $dst -Force
                    Write-Host "   delete $dst" -ForegroundColor Magenta
                }
            }
        }
    }

    # 清理空目录
    if (-not $Context.DryRun) {
        foreach ($item in $Items) {
            $itemPath = Join-Path $TargetRoot $item
            if (-not (Test-Path $itemPath -PathType Container)) { continue }
            Get-ChildItem -Path $itemPath -Recurse -Directory |
            Sort-Object -Property FullName -Descending |
            ForEach-Object {
                if (-not (Get-ChildItem -LiteralPath $_.FullName -Force | Select-Object -First 1)) {
                    Remove-Item -LiteralPath $_.FullName -Force
                }
            }
        }
    }
}

# Render 目录的孤儿检测（目标存在但源模板已被删除）
function Sync-RenderOrphans {
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [Parameter(Mandatory)] [string]    $SourceDir,
        [Parameter(Mandatory)] [string]    $DestinationDir,
        [Parameter(Mandatory)] [string]    $SourceGlob,
        [Parameter(Mandatory)] [string]    $TargetGlob
    )

    if (-not (Test-Path $DestinationDir)) { return }
    $expected = @()
    if (Test-Path $SourceDir) {
        $expected = Get-ChildItem -Path $SourceDir -Filter $SourceGlob | ForEach-Object {
            ($_.Name -replace '\.template', '')
        }
    }

    Get-ChildItem -Path $DestinationDir -Filter $TargetGlob | ForEach-Object {
        $orphanFile = $_
        if ($expected -contains $orphanFile.Name) { return }
        $decision = Resolve-DeleteDecisionInternal -Context $Context -Path $orphanFile.FullName
        switch ($decision) {
            'delete' {
                if ($Context.DryRun) {
                    Write-Host "   dryrun-delete $($orphanFile.FullName)" -ForegroundColor DarkGray
                }
                else {
                    Remove-Item -LiteralPath $orphanFile.FullName -Force
                    Write-Host "   delete $($orphanFile.FullName)" -ForegroundColor Magenta
                }
            }
            'keep' { Write-Host "   keep   $($orphanFile.FullName) (orphan)" -ForegroundColor DarkYellow }
            'abort' { throw '用户中止' }
        }
    }
}

# Tree 渲染的孤儿检测：递归对比目标整棵子树，删除不在 expected 列表里的文件，再清空目录。
function Sync-TreeOrphans {
    param(
        [Parameter(Mandatory)] [hashtable] $Context,
        [Parameter(Mandatory)] [string]    $DestinationDir,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[string]] $ExpectedRelPaths
    )

    if (-not (Test-Path $DestinationDir)) { return }

    $expectedSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $ExpectedRelPaths) { [void]$expectedSet.Add($p) }

    $allFiles = @(Get-ChildItem -LiteralPath $DestinationDir -Recurse -File)
    foreach ($file in $allFiles) {
        $rel = [System.IO.Path]::GetRelativePath($DestinationDir, $file.FullName).Replace('\', '/')
        if ($expectedSet.Contains($rel)) { continue }
        $decision = Resolve-DeleteDecisionInternal -Context $Context -Path $file.FullName
        switch ($decision) {
            'delete' {
                if ($Context.DryRun) {
                    Write-Host "   dryrun-delete $($file.FullName)" -ForegroundColor DarkGray
                }
                else {
                    Remove-Item -LiteralPath $file.FullName -Force
                    Write-Host "   delete $($file.FullName)" -ForegroundColor Magenta
                }
            }
            'keep' { Write-Host "   keep   $($file.FullName) (orphan)" -ForegroundColor DarkYellow }
            'abort' { throw '用户中止' }
        }
    }

    # 删完文件后清空目录（自下而上）
    if (-not $Context.DryRun) {
        $allDirs = @(Get-ChildItem -LiteralPath $DestinationDir -Recurse -Directory) |
            Sort-Object -Property FullName -Descending
        foreach ($d in $allDirs) {
            if (-not (Get-ChildItem -LiteralPath $d.FullName -Force | Select-Object -First 1)) {
                Remove-Item -LiteralPath $d.FullName -Force
            }
        }
    }
}
