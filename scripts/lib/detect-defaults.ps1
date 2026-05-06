<#
.SYNOPSIS
    Harness Engineering · 项目默认值探测器（target-agnostic, read-only）。

.DESCRIPTION
    根据采用方仓库现有内容，推断 ProjectName / PrimaryLanguage / TechStack /
    TestCommand / LintCommand 的合理默认值，作为 prompt 的 placeholder。

    探测严格只读，绝不写盘。任何无法判定的字段返回 $null（让上层选择是否
    fallback 到 "<未配置>"）。
#>

Set-StrictMode -Version Latest

# ----------------------------------------------------------------------------
# 工具函数
# ----------------------------------------------------------------------------
function Test-AnyFile {
    param([string]$Root, [string[]]$Patterns)
    foreach ($p in $Patterns) {
        $hit = Get-ChildItem -Path $Root -Filter $p -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $true }
        # 尝试一级子目录（src/ 等常见位置）
        $hit2 = Get-ChildItem -Path $Root -Filter $p -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit2) { return $true }
    }
    return $false
}

function Read-FirstLineMatching {
    param([string]$Path, [string]$Pattern)
    if (-not (Test-Path $Path)) { return $null }
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ($line -match $Pattern) { return $matches[0] }
    }
    return $null
}

# ----------------------------------------------------------------------------
# ProjectName
# ----------------------------------------------------------------------------
function Get-DetectedProjectName {
    param([string]$Root)

    # 1. git remote
    try {
        Push-Location $Root
        $url = & git remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and $url) {
            $leaf = ($url -split '[/\\]')[-1] -replace '\.git$', ''
            if ($leaf) { return $leaf }
        }
    }
    catch { }
    finally { Pop-Location }

    # 2. package.json.name
    $pkg = Join-Path $Root 'package.json'
    if (Test-Path $pkg) {
        try {
            $obj = Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json
            if ($obj.name) { return [string]$obj.name }
        }
        catch { }
    }

    # 3. *.csproj / *.sln / *.slnx 文件名
    foreach ($pattern in @('*.slnx', '*.sln', '*.csproj')) {
        $hit = Get-ChildItem -Path $Root -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return [System.IO.Path]::GetFileNameWithoutExtension($hit.Name) }
    }

    # 4. leaf
    return Split-Path -Leaf $Root
}

# ----------------------------------------------------------------------------
# PrimaryLanguage
# ----------------------------------------------------------------------------
function Get-DetectedLanguage {
    param([string]$Root)

    if (Test-AnyFile -Root $Root -Patterns @('*.csproj', '*.sln', '*.slnx')) { return 'C#' }
    if (Test-AnyFile -Root $Root -Patterns @('pyproject.toml', 'setup.py', 'requirements.txt')) { return 'Python' }
    if (Test-AnyFile -Root $Root -Patterns @('tsconfig.json')) { return 'TypeScript' }
    if (Test-AnyFile -Root $Root -Patterns @('package.json')) { return 'JavaScript' }
    if (Test-AnyFile -Root $Root -Patterns @('go.mod')) { return 'Go' }
    if (Test-AnyFile -Root $Root -Patterns @('Cargo.toml')) { return 'Rust' }
    if (Test-AnyFile -Root $Root -Patterns @('pom.xml', 'build.gradle', 'build.gradle.kts')) { return 'Java' }
    return $null
}

# ----------------------------------------------------------------------------
# TechStack（在语言基础上加二次特征）
# ----------------------------------------------------------------------------
function Get-DetectedTechStack {
    param([string]$Root, [string]$Language)

    if ($Language -eq 'C#') {
        # 探测 ASP.NET Core / Aspire
        $csprojs = Get-ChildItem -Path $Root -Filter '*.csproj' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue
        $hasAspNet = $false
        $hasAspire = $false
        foreach ($f in $csprojs) {
            $content = [System.IO.File]::ReadAllText($f.FullName)
            if ($content -match 'Microsoft\.AspNetCore') { $hasAspNet = $true }
            if ($content -match 'Aspire') { $hasAspire = $true }
        }
        $tfm = $null
        $globalJson = Join-Path $Root 'global.json'
        if (Test-Path $globalJson) {
            try {
                $g = Get-Content $globalJson -Raw | ConvertFrom-Json
                if ($g.sdk -and $g.sdk.version) {
                    $major = ($g.sdk.version -split '\.')[0]
                    $tfm = ".NET $major"
                }
            }
            catch { }
        }
        if (-not $tfm) {
            foreach ($f in $csprojs) {
                $content = [System.IO.File]::ReadAllText($f.FullName)
                if ($content -match '<TargetFramework[s]?>net(\d+)\.\d+') {
                    $tfm = ".NET $($matches[1])"
                    break
                }
            }
        }
        $parts = @()
        if ($tfm) { $parts += $tfm } else { $parts += '.NET' }
        if ($hasAspNet) { $parts += 'ASP.NET Core' }
        if ($hasAspire) { $parts += 'Aspire' }
        return ($parts -join ' + ')
    }

    if ($Language -in @('TypeScript', 'JavaScript')) {
        $pkgPath = Join-Path $Root 'package.json'
        if (Test-Path $pkgPath) {
            try {
                $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
                $deps = @{}
                if ($pkg.dependencies) { $pkg.dependencies.PSObject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value } }
                if ($pkg.devDependencies) { $pkg.devDependencies.PSObject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value } }
                if (Test-Path (Join-Path $Root 'next.config.js')) { return 'Next.js + React' }
                if (Test-Path (Join-Path $Root 'next.config.ts')) { return 'Next.js + React' }
                if (Test-Path (Join-Path $Root 'next.config.mjs')) { return 'Next.js + React' }
                if ($deps.ContainsKey('next')) { return 'Next.js + React' }
                if ($deps.ContainsKey('react-native')) { return 'React Native' }
                if ($deps.ContainsKey('vite') -and $deps.ContainsKey('react')) { return 'Vite + React' }
                if ($deps.ContainsKey('vite') -and $deps.ContainsKey('vue')) { return 'Vite + Vue' }
                if ($deps.ContainsKey('vite')) { return 'Vite' }
                if ($deps.ContainsKey('@nestjs/core')) { return 'NestJS' }
                if ($deps.ContainsKey('react')) { return 'React' }
                if ($deps.ContainsKey('vue')) { return 'Vue' }
                if ($deps.ContainsKey('express')) { return 'Express + Node.js' }
                if ($deps.ContainsKey('fastify')) { return 'Fastify + Node.js' }
            }
            catch { }
        }
        return $Language
    }

    if ($Language -eq 'Python') {
        $py = Join-Path $Root 'pyproject.toml'
        if (Test-Path $py) {
            $content = [System.IO.File]::ReadAllText($py)
            if ($content -match 'fastapi') { return 'Python + FastAPI' }
            if ($content -match 'django') { return 'Python + Django' }
            if ($content -match 'flask') { return 'Python + Flask' }
        }
        return 'Python'
    }

    if ($Language) { return $Language }
    return $null
}

# ----------------------------------------------------------------------------
# TestCommand
# ----------------------------------------------------------------------------
function Get-DetectedTestCommand {
    param([string]$Root, [string]$Language)

    if ($Language -eq 'C#') { return 'dotnet test' }
    if ($Language -eq 'Go') { return 'go test ./...' }
    if ($Language -eq 'Rust') { return 'cargo test' }

    if ($Language -in @('TypeScript', 'JavaScript')) {
        $pkgPath = Join-Path $Root 'package.json'
        if (Test-Path $pkgPath) {
            try {
                $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
                $hasTest = $pkg.scripts -and $pkg.scripts.PSObject.Properties.Name -contains 'test'
                if ($hasTest) {
                    if (Test-Path (Join-Path $Root 'pnpm-lock.yaml')) { return 'pnpm test' }
                    if (Test-Path (Join-Path $Root 'yarn.lock')) { return 'yarn test' }
                    if (Test-Path (Join-Path $Root 'bun.lockb')) { return 'bun test' }
                    return 'npm test'
                }
            }
            catch { }
        }
    }

    if ($Language -eq 'Python') {
        $py = Join-Path $Root 'pyproject.toml'
        if (Test-Path $py) {
            $c = [System.IO.File]::ReadAllText($py)
            if ($c -match 'pytest') { return 'pytest' }
        }
        if (Test-Path (Join-Path $Root 'pytest.ini')) { return 'pytest' }
        return 'python -m unittest'
    }

    if ($Language -eq 'Java') {
        if (Test-Path (Join-Path $Root 'pom.xml')) { return 'mvn test' }
        if (Test-Path (Join-Path $Root 'build.gradle')) { return 'gradle test' }
        if (Test-Path (Join-Path $Root 'build.gradle.kts')) { return 'gradle test' }
    }

    return $null
}

# ----------------------------------------------------------------------------
# LintCommand
# ----------------------------------------------------------------------------
function Get-DetectedLintCommand {
    param([string]$Root, [string]$Language)

    if ($Language -eq 'C#') { return 'dotnet format --verify-no-changes' }
    if ($Language -eq 'Go') { return 'gofmt -l . && go vet ./...' }
    if ($Language -eq 'Rust') { return 'cargo clippy -- -D warnings' }

    if ($Language -in @('TypeScript', 'JavaScript')) {
        $pkgPath = Join-Path $Root 'package.json'
        if (Test-Path $pkgPath) {
            try {
                $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
                $hasLint = $pkg.scripts -and $pkg.scripts.PSObject.Properties.Name -contains 'lint'
                if ($hasLint) {
                    if (Test-Path (Join-Path $Root 'pnpm-lock.yaml')) { return 'pnpm run lint' }
                    if (Test-Path (Join-Path $Root 'yarn.lock')) { return 'yarn lint' }
                    return 'npm run lint'
                }
            }
            catch { }
        }
        $eslint = Get-ChildItem -Path $Root -Filter '.eslintrc*' -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($eslint -or (Test-Path (Join-Path $Root 'eslint.config.js'))) { return 'eslint .' }
    }

    if ($Language -eq 'Python') {
        $py = Join-Path $Root 'pyproject.toml'
        if (Test-Path $py) {
            $c = [System.IO.File]::ReadAllText($py)
            if ($c -match 'ruff') { return 'ruff check .' }
            if ($c -match '\bblack\b') { return 'black --check .' }
        }
    }

    return $null
}

# ----------------------------------------------------------------------------
# 综合
# ----------------------------------------------------------------------------
function Get-ProjectDefaults {
    param([Parameter(Mandatory)] [string] $Root)

    $name = Get-DetectedProjectName -Root $Root
    $lang = Get-DetectedLanguage -Root $Root
    $stack = Get-DetectedTechStack -Root $Root -Language $lang
    $test = Get-DetectedTestCommand -Root $Root -Language $lang
    $lint = Get-DetectedLintCommand -Root $Root -Language $lang

    return [ordered]@{
        ProjectName     = $name
        PrimaryLanguage = $lang
        TechStack       = $stack
        TestCommand     = $test
        LintCommand     = $lint
    }
}
