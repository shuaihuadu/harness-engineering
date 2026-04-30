#!/usr/bin/env bash
# Harness Engineering · 项目默认值探测器（target-agnostic, read-only）
#
# 暴露函数：
#   detect_project_defaults <root>
# 通过设置全局变量返回（避免子 shell 丢上下文）：
#   DETECTED_PROJECT_NAME / DETECTED_PRIMARY_LANGUAGE / DETECTED_TECH_STACK
#   DETECTED_TEST_COMMAND / DETECTED_LINT_COMMAND
# 任何字段无法判定 → 设置为空字符串

set -euo pipefail

_any_file() {
    local root="$1"; shift
    local pat
    for pat in "$@"; do
        if compgen -G "$root/$pat" >/dev/null 2>&1; then return 0; fi
        # 一级递归（最多 2 层深）
        if find "$root" -maxdepth 3 -type f -name "$pat" 2>/dev/null | head -n1 | grep -q .; then return 0; fi
    done
    return 1
}

_detect_project_name() {
    local root="$1"

    # 1. git remote
    local url
    url=$(git -C "$root" remote get-url origin 2>/dev/null || echo "")
    if [[ -n "$url" ]]; then
        local leaf="${url##*/}"
        leaf="${leaf%.git}"
        [[ -n "$leaf" ]] && { echo "$leaf"; return; }
    fi

    # 2. package.json
    if [[ -f "$root/package.json" ]] && command -v jq >/dev/null 2>&1; then
        local n
        n=$(jq -r '.name // ""' "$root/package.json" 2>/dev/null || echo "")
        [[ -n "$n" && "$n" != "null" ]] && { echo "$n"; return; }
    fi

    # 3. *.csproj / *.sln / *.slnx
    local pattern
    for pattern in '*.slnx' '*.sln' '*.csproj'; do
        local hit
        hit=$(find "$root" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | head -n1)
        if [[ -n "$hit" ]]; then
            local base; base=$(basename "$hit")
            echo "${base%.*}"; return
        fi
    done

    # 4. leaf
    basename "$root"
}

_detect_language() {
    local root="$1"
    if _any_file "$root" '*.csproj' '*.sln' '*.slnx'; then echo 'C#'; return; fi
    if _any_file "$root" 'pyproject.toml' 'setup.py' 'requirements.txt'; then echo 'Python'; return; fi
    if _any_file "$root" 'tsconfig.json'; then echo 'TypeScript'; return; fi
    if _any_file "$root" 'package.json'; then echo 'JavaScript'; return; fi
    if _any_file "$root" 'go.mod'; then echo 'Go'; return; fi
    if _any_file "$root" 'Cargo.toml'; then echo 'Rust'; return; fi
    if _any_file "$root" 'pom.xml' 'build.gradle' 'build.gradle.kts'; then echo 'Java'; return; fi
    echo ""
}

_detect_tech_stack() {
    local root="$1" lang="$2"

    if [[ "$lang" == "C#" ]]; then
        local has_aspnet=0 has_aspire=0
        local f
        while IFS= read -r f; do
            grep -q 'Microsoft\.AspNetCore' "$f" 2>/dev/null && has_aspnet=1
            grep -q 'Aspire' "$f" 2>/dev/null && has_aspire=1
        done < <(find "$root" -maxdepth 4 -name '*.csproj' -type f 2>/dev/null)

        local tfm=""
        if [[ -f "$root/global.json" ]] && command -v jq >/dev/null 2>&1; then
            local v; v=$(jq -r '.sdk.version // ""' "$root/global.json" 2>/dev/null || echo "")
            [[ -n "$v" && "$v" != "null" ]] && tfm=".NET ${v%%.*}"
        fi
        if [[ -z "$tfm" ]]; then
            local hit
            hit=$(grep -hoE '<TargetFramework[s]?>net[0-9]+\.[0-9]+' "$root"/*.csproj 2>/dev/null | head -n1 | grep -oE 'net[0-9]+' | sed 's/net/.NET /')
            [[ -n "$hit" ]] && tfm="$hit"
        fi
        local parts="${tfm:-.NET}"
        [[ $has_aspnet -eq 1 ]] && parts="$parts + ASP.NET Core"
        [[ $has_aspire -eq 1 ]] && parts="$parts + Aspire"
        echo "$parts"; return
    fi

    if [[ "$lang" == "TypeScript" || "$lang" == "JavaScript" ]] && [[ -f "$root/package.json" ]] && command -v jq >/dev/null 2>&1; then
        local pkg="$root/package.json"
        local deps; deps=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys | join(",")' "$pkg" 2>/dev/null)
        [[ -f "$root/next.config.js" || -f "$root/next.config.ts" || -f "$root/next.config.mjs" ]] && { echo 'Next.js + React'; return; }
        case ",$deps," in
            *,next,*)         echo 'Next.js + React'; return ;;
            *,react-native,*) echo 'React Native'; return ;;
        esac
        local has_vite=0; [[ ",$deps," == *,vite,* ]] && has_vite=1
        if [[ $has_vite -eq 1 && ",$deps," == *,react,* ]]; then echo 'Vite + React'; return; fi
        if [[ $has_vite -eq 1 && ",$deps," == *,vue,* ]]; then echo 'Vite + Vue'; return; fi
        [[ $has_vite -eq 1 ]] && { echo 'Vite'; return; }
        case ",$deps," in
            *,@nestjs/core,*) echo 'NestJS'; return ;;
            *,react,*)        echo 'React'; return ;;
            *,vue,*)          echo 'Vue'; return ;;
            *,express,*)      echo 'Express + Node.js'; return ;;
            *,fastify,*)      echo 'Fastify + Node.js'; return ;;
        esac
        echo "$lang"; return
    fi

    if [[ "$lang" == "Python" ]]; then
        if [[ -f "$root/pyproject.toml" ]]; then
            grep -q 'fastapi' "$root/pyproject.toml" 2>/dev/null && { echo 'Python + FastAPI'; return; }
            grep -q 'django'  "$root/pyproject.toml" 2>/dev/null && { echo 'Python + Django'; return; }
            grep -q 'flask'   "$root/pyproject.toml" 2>/dev/null && { echo 'Python + Flask'; return; }
        fi
        echo 'Python'; return
    fi

    [[ -n "$lang" ]] && echo "$lang" || echo ""
}

_detect_test_command() {
    local root="$1" lang="$2"
    case "$lang" in
        'C#') echo 'dotnet test'; return ;;
        'Go') echo 'go test ./...'; return ;;
        'Rust') echo 'cargo test'; return ;;
    esac

    if [[ "$lang" == "TypeScript" || "$lang" == "JavaScript" ]] && [[ -f "$root/package.json" ]] && command -v jq >/dev/null 2>&1; then
        local has_test; has_test=$(jq -r '.scripts.test // ""' "$root/package.json" 2>/dev/null)
        if [[ -n "$has_test" && "$has_test" != "null" ]]; then
            [[ -f "$root/pnpm-lock.yaml" ]] && { echo 'pnpm test'; return; }
            [[ -f "$root/yarn.lock"     ]] && { echo 'yarn test'; return; }
            [[ -f "$root/bun.lockb"     ]] && { echo 'bun test'; return; }
            echo 'npm test'; return
        fi
    fi

    if [[ "$lang" == "Python" ]]; then
        [[ -f "$root/pyproject.toml" ]] && grep -q 'pytest' "$root/pyproject.toml" 2>/dev/null && { echo 'pytest'; return; }
        [[ -f "$root/pytest.ini" ]] && { echo 'pytest'; return; }
        echo 'python -m unittest'; return
    fi

    if [[ "$lang" == "Java" ]]; then
        [[ -f "$root/pom.xml" ]] && { echo 'mvn test'; return; }
        [[ -f "$root/build.gradle" || -f "$root/build.gradle.kts" ]] && { echo 'gradle test'; return; }
    fi

    echo ""
}

_detect_lint_command() {
    local root="$1" lang="$2"
    case "$lang" in
        'C#') echo 'dotnet format --verify-no-changes'; return ;;
        'Go') echo 'gofmt -l . && go vet ./...'; return ;;
        'Rust') echo 'cargo clippy -- -D warnings'; return ;;
    esac

    if [[ "$lang" == "TypeScript" || "$lang" == "JavaScript" ]] && [[ -f "$root/package.json" ]] && command -v jq >/dev/null 2>&1; then
        local has_lint; has_lint=$(jq -r '.scripts.lint // ""' "$root/package.json" 2>/dev/null)
        if [[ -n "$has_lint" && "$has_lint" != "null" ]]; then
            [[ -f "$root/pnpm-lock.yaml" ]] && { echo 'pnpm run lint'; return; }
            [[ -f "$root/yarn.lock"     ]] && { echo 'yarn lint'; return; }
            echo 'npm run lint'; return
        fi
        if compgen -G "$root/.eslintrc*" >/dev/null 2>&1 || [[ -f "$root/eslint.config.js" ]]; then
            echo 'eslint .'; return
        fi
    fi

    if [[ "$lang" == "Python" && -f "$root/pyproject.toml" ]]; then
        grep -q 'ruff'  "$root/pyproject.toml" 2>/dev/null && { echo 'ruff check .'; return; }
        grep -q 'black' "$root/pyproject.toml" 2>/dev/null && { echo 'black --check .'; return; }
    fi

    echo ""
}

detect_project_defaults() {
    local root="$1"
    DETECTED_PROJECT_NAME=$(_detect_project_name "$root")
    DETECTED_PRIMARY_LANGUAGE=$(_detect_language "$root")
    DETECTED_TECH_STACK=$(_detect_tech_stack "$root" "$DETECTED_PRIMARY_LANGUAGE")
    DETECTED_TEST_COMMAND=$(_detect_test_command "$root" "$DETECTED_PRIMARY_LANGUAGE")
    DETECTED_LINT_COMMAND=$(_detect_lint_command "$root" "$DETECTED_PRIMARY_LANGUAGE")
}
