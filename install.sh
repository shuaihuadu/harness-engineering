#!/usr/bin/env bash
# Harness Engineering · 多工具集成统一入口（bash 端）
#
# 用法：
#   ./install.sh --target-repo /path/to/repo [--targets copilot,claude-code] \
#                [--test-command 'dotnet test'] [--lint-command 'dotnet format --verify-no-changes'] \
#                [--harness-repo-ref .he] [--non-interactive]
#
# 依赖：bash 4+，jq

# ----------------------------------------------------------------------------
# Bootstrap：若当前 bash < 4（典型为 macOS 自带的 /bin/bash 3.2），
# 尝试重新执行到一个兼容的 bash 4+。
# 注意：本段必须保持 bash 3.2 兼容，不能用 declare -A / ${var,,} 等特性。
# ----------------------------------------------------------------------------
if [ -z "${HARNESS_BASH_REEXEC:-}" ] && { [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; }; then
    for _he_candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash; do
        if [ -x "$_he_candidate" ]; then
            export HARNESS_BASH_REEXEC=1
            exec "$_he_candidate" "$0" "$@"
        fi
    done
    if command -v bash >/dev/null 2>&1; then
        _he_found="$(command -v bash)"
        _he_ver="$("$_he_found" -c 'echo "${BASH_VERSINFO[0]:-0}"' 2>/dev/null || echo 0)"
        if [ "${_he_ver:-0}" -ge 4 ] 2>/dev/null; then
            export HARNESS_BASH_REEXEC=1
            exec "$_he_found" "$0" "$@"
        fi
    fi
    echo "错误：本脚本需要 bash 4 及以上版本（当前: ${BASH_VERSION:-unknown}）。" >&2
    echo "       Error: this script requires bash 4+ (current: ${BASH_VERSION:-unknown})." >&2
    echo "       macOS 用户请安装 Homebrew bash 后重试：brew install bash" >&2
    echo "       macOS users: install Homebrew bash and retry: brew install bash" >&2
    exit 1
fi
unset HARNESS_BASH_REEXEC

set -euo pipefail

# ----------------------------------------------------------------------------
# 参数
# ----------------------------------------------------------------------------
TARGET_REPO=""
TARGETS="copilot"
TEST_COMMAND=""
LINT_COMMAND=""
HARNESS_REPO_REF=""
VENDOR_HARNESS_TO=".he"
VENDOR_HARNESS_TO_EXPLICIT=0
NO_VENDOR=0
COPILOT_AGENTS=""
NON_INTERACTIVE=0
FORCE=0
NO_DELETE=0
DRY_RUN=0

OVERWRITE_ALL=0
DELETE_ALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-repo)        TARGET_REPO="$2";        shift 2 ;;
        --targets)            TARGETS="$2";            shift 2 ;;
        --test-command)       TEST_COMMAND="$2";       shift 2 ;;
        --lint-command)       LINT_COMMAND="$2";       shift 2 ;;
        --harness-repo-ref)   HARNESS_REPO_REF="$2";   shift 2 ;;
        --vendor-harness-to)  VENDOR_HARNESS_TO="$2"; VENDOR_HARNESS_TO_EXPLICIT=1; shift 2 ;;
        --no-vendor)          NO_VENDOR=1;             shift ;;
        --copilot-agents)     COPILOT_AGENTS="$2";     shift 2 ;;
        --non-interactive)    NON_INTERACTIVE=1;       shift ;;
        --force)              FORCE=1;                 shift ;;
        --no-delete)          NO_DELETE=1;             shift ;;
        --dry-run)            DRY_RUN=1;               shift ;;
        -h|--help)            sed -n '4,12p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

# Force 隐含 non-interactive
[[ $FORCE -eq 1 ]] && NON_INTERACTIVE=1

[[ -z "$TARGET_REPO" ]] && { echo "错误：必须指定 --target-repo" >&2; exit 2; }
[[ ! -d "$TARGET_REPO" ]] && { echo "错误：目录不存在：$TARGET_REPO" >&2; exit 1; }
TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"

# ----------------------------------------------------------------------------
# 路径
# ----------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$REPO_ROOT/scripts/lib"
INTEGRATIONS_ROOT="$REPO_ROOT/agents/_integrations"

command -v jq >/dev/null 2>&1 || { echo "错误：本脚本依赖 jq，请先安装（apt/brew install jq）" >&2; exit 1; }

HARNESS_VERSION="0.0.0"
[[ -f "$REPO_ROOT/VERSION" ]] && HARNESS_VERSION="$(tr -d '[:space:]' <"$REPO_ROOT/VERSION")"

# manifest 临时收集（sync-engine 通过 MANIFEST_TMP 追加）
MANIFEST_TMP=""
if [[ $DRY_RUN -eq 0 ]]; then
    MANIFEST_TMP="$(mktemp)"
fi
export MANIFEST_TMP TARGET_REPO

# shellcheck source=scripts/lib/sync-engine.sh
source "$LIB_DIR/sync-engine.sh"
# shellcheck source=scripts/lib/target-runner.sh
source "$LIB_DIR/target-runner.sh"
# shellcheck source=scripts/lib/detect-defaults.sh
source "$LIB_DIR/detect-defaults.sh"

# ----------------------------------------------------------------------------
# 验证 targets
# ----------------------------------------------------------------------------
IFS=',' read -ra TARGETS_ARR <<<"$TARGETS"
for t in "${TARGETS_ARR[@]}"; do
    [[ -f "$INTEGRATIONS_ROOT/$t/target.json" ]] || { echo "未知 target：${t}（在 ${INTEGRATIONS_ROOT} 下未找到 ${t}/target.json）" >&2; exit 1; }
done

# ----------------------------------------------------------------------------
# 占位符收集（CLI > manifest > 探测 > 交互 / 空默认）
# ----------------------------------------------------------------------------
UNCONFIGURED='<未配置>'

# 1) 探测
DETECTED_PROJECT_NAME=""
DETECTED_PRIMARY_LANGUAGE=""
DETECTED_TECH_STACK=""
DETECTED_TEST_COMMAND=""
DETECTED_LINT_COMMAND=""
detect_project_defaults "$TARGET_REPO"

# 2) 读取上次 manifest replacements
declare -A PRIOR
# 优先按 CLI 显式 vendor_dir 寻 manifest；否则尝试默认 .he/，再退化扫描顶层目录
PRIOR_MANIFEST_PATH=""
PRIOR_MANIFEST_VENDOR_DIR=""
if [[ $VENDOR_HARNESS_TO_EXPLICIT -eq 1 && -n "$VENDOR_HARNESS_TO" ]]; then
    candidate="$TARGET_REPO/$VENDOR_HARNESS_TO/manifest.json"
    [[ -f "$candidate" ]] && PRIOR_MANIFEST_PATH="$candidate" && PRIOR_MANIFEST_VENDOR_DIR="$VENDOR_HARNESS_TO"
fi
if [[ -z "$PRIOR_MANIFEST_PATH" && -f "$TARGET_REPO/.he/manifest.json" ]]; then
    PRIOR_MANIFEST_PATH="$TARGET_REPO/.he/manifest.json"
    PRIOR_MANIFEST_VENDOR_DIR=".he"
fi
if [[ -z "$PRIOR_MANIFEST_PATH" ]]; then
    # 顶层目录扫一圈：识别 schema=v1 + harness_version 的 manifest（自定义 vendor_dir 场景）
    while IFS= read -r mf; do
        if jq -e '(.schema=="v1") and (.harness_version != null)' "$mf" >/dev/null 2>&1; then
            PRIOR_MANIFEST_PATH="$mf"
            PRIOR_MANIFEST_VENDOR_DIR=$(jq -r '.vendor_dir // ""' "$mf" 2>/dev/null || echo "")
            [[ -z "$PRIOR_MANIFEST_VENDOR_DIR" ]] && PRIOR_MANIFEST_VENDOR_DIR=$(basename "$(dirname "$mf")")
            break
        fi
    done < <(find "$TARGET_REPO" -mindepth 2 -maxdepth 2 -name 'manifest.json' -print 2>/dev/null)
fi
PRIOR_VERSION=""
if [[ -n "$PRIOR_MANIFEST_PATH" && -f "$PRIOR_MANIFEST_PATH" ]]; then
    while IFS=$'\t' read -r k v; do
        [[ -n "$k" ]] && PRIOR["$k"]="$v"
    done < <(jq -r '(.replacements // {}) | to_entries[]? | [.key, .value] | @tsv' "$PRIOR_MANIFEST_PATH" 2>/dev/null || true)
    PRIOR_VERSION=$(jq -r '.harness_version // ""' "$PRIOR_MANIFEST_PATH" 2>/dev/null || echo "")
fi

# 3) 解析单字段
resolve_placeholder() {
    # $1=var_name $2=manifest_key $3=detected $4=prompt
    local var_name="$1" mkey="$2" detected="$3" prompt="$4"
    local cli_val="${!var_name}"
    if [[ -n "$cli_val" ]]; then return 0; fi

    local manifest_val="${PRIOR[$mkey]:-}"
    local default=""
    if [[ -n "$manifest_val" ]]; then default="$manifest_val"
    elif [[ -n "$detected" ]]; then default="$detected"
    fi

    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        printf -v "$var_name" '%s' "$default"
        return 0
    fi

    local hint; if [[ -n "$default" ]]; then hint=" [$default]"; else hint=" [回车跳过 / press Enter to skip]"; fi
    local value; read -r -p "$prompt$hint: " value
    [[ -z "$value" ]] && value="$default"
    printf -v "$var_name" '%s' "$value"
}

# 3b) 命令选择：菜单 + 自定义 + 跳过
#     非交互模式直接走 manifest > detected 的回退链
resolve_command_with_menu() {
    # $1=var_name $2=manifest_key $3=detected $4=title $5=options_array_name
    local var_name="$1" mkey="$2" detected="$3" title="$4" opts_name="$5"
    local cli_val="${!var_name}"
    if [[ -n "$cli_val" ]]; then return 0; fi

    local manifest_val="${PRIOR[$mkey]:-}"
    local preferred=""
    if [[ -n "$manifest_val" ]]; then preferred="$manifest_val"
    elif [[ -n "$detected" ]]; then preferred="$detected"
    fi

    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        printf -v "$var_name" '%s' "$preferred"
        return 0
    fi

    # 拷贝候选数组，必要时把推荐项插到首位
    local -n _src="$opts_name"
    local list=()
    local default_index=""
    if [[ -n "$preferred" ]]; then
        list+=("$preferred")
        default_index=1
        local opt
        for opt in "${_src[@]}"; do
            [[ "$opt" == "$preferred" ]] && continue
            list+=("$opt")
        done
    else
        list=("${_src[@]}")
    fi

    echo
    echo "    $title"
    local i
    for i in "${!list[@]}"; do
        local n=$((i + 1))
        local line
        printf -v line '      %d) %s' "$n" "${list[$i]}"
        if [[ "$n" == "$default_index" ]]; then line+='    (推荐 / detected)'; fi
        echo "$line"
    done
    echo '      c) 自定义 / Custom...'
    echo '      s) 跳过 / Skip (会渲染为 <未配置>)'

    local default_label="c"
    [[ -n "$default_index" ]] && default_label="$default_index"
    local choice
    read -r -p "    选择 / Choose [$default_label]: " choice
    [[ -z "$choice" ]] && choice="$default_label"
    choice="${choice,,}"
    choice="${choice// /}"

    if [[ "$choice" == "s" ]]; then
        printf -v "$var_name" '%s' ""
        return 0
    fi
    if [[ "$choice" == "c" ]]; then
        local custom
        read -r -p '    自定义命令 / Custom command: ' custom
        if [[ -z "$custom" ]]; then
            printf -v "$var_name" '%s' "$preferred"
        else
            printf -v "$var_name" '%s' "$custom"
        fi
        return 0
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#list[@]} )); then
        printf -v "$var_name" '%s' "${list[$((choice - 1))]}"
        return 0
    fi
    echo "    [!] 无效选择 '$choice'，使用推荐值 / Invalid choice, falling back to recommended" >&2
    printf -v "$var_name" '%s' "$preferred"
}

TEST_OPTIONS=(
    'dotnet test'
    'npm test'
    'pnpm test'
    'yarn test'
    'pytest'
    'cargo test'
    'go test ./...'
    'mvn test'
    'gradle test'
)
LINT_OPTIONS=(
    'dotnet format --verify-no-changes'
    'npm run lint'
    'pnpm run lint'
    'eslint .'
    'ruff check .'
    'black --check .'
    'cargo clippy -- -D warnings'
    'gofmt -l . && go vet ./...'
    'mvn checkstyle:check'
)

echo
echo "==> Harness Engineering v$HARNESS_VERSION · 集成同步 / Integration sync"
echo "    目标仓库 / Target repo : $TARGET_REPO"
echo "    安装目标 / Targets     : $TARGETS"
echo "    交互模式 / Interactive : $([[ $NON_INTERACTIVE -eq 1 ]] && echo '否 / no' || echo '是 / yes')"

if [[ -n "$DETECTED_TEST_COMMAND$DETECTED_LINT_COMMAND" ]]; then
    echo
    echo '    自动探测 / Auto-detected:'
    [[ -n "$DETECTED_TEST_COMMAND" ]] && echo "      TestCommand = $DETECTED_TEST_COMMAND"
    [[ -n "$DETECTED_LINT_COMMAND" ]] && echo "      LintCommand = $DETECTED_LINT_COMMAND"
fi
prior_count=0
set +u; prior_count=${#PRIOR[@]}; set -u
if [[ $prior_count -gt 0 ]]; then
    echo
    echo "    检测到上次 manifest（v${PRIOR_VERSION}），将作为默认值预填 / Detected previous manifest, prefilling defaults"
fi
echo

resolve_command_with_menu TEST_COMMAND 'TEST_COMMAND' "$DETECTED_TEST_COMMAND" '测试命令 / Test command (TEST_COMMAND)'         TEST_OPTIONS
resolve_command_with_menu LINT_COMMAND 'LINT_COMMAND' "$DETECTED_LINT_COMMAND" '代码风格检查命令 / Lint command (LINT_COMMAND)' LINT_OPTIONS

# Vendor 目录：CLI 显式传入 > 上次 manifest.vendor_dir > 默认 .he
if [[ $NO_VENDOR -eq 0 && $VENDOR_HARNESS_TO_EXPLICIT -eq 0 ]]; then
    vendor_default="$VENDOR_HARNESS_TO"
    [[ -n "$PRIOR_MANIFEST_VENDOR_DIR" ]] && vendor_default="$PRIOR_MANIFEST_VENDOR_DIR"
    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        read -r -p "Vendor 目录 / Vendor directory (relative to TargetRepo) [$vendor_default]: " vendor_input
        if [[ -z "$vendor_input" ]]; then
            VENDOR_HARNESS_TO="$vendor_default"
        else
            VENDOR_HARNESS_TO="$vendor_input"
        fi
    else
        VENDOR_HARNESS_TO="$vendor_default"
    fi
fi

if [[ $NO_VENDOR -eq 1 ]]; then
    default_ref="${PRIOR[HARNESS_REPO_REF]:-https://github.com/shuaihuadu/harness-engineering}"
    resolve_placeholder HARNESS_REPO_REF 'HARNESS_REPO_REF' "$default_ref" '规范引用 / Harness repo ref (HARNESS_REPO_REF, path or URL)'
    [[ -z "$HARNESS_REPO_REF" ]] && HARNESS_REPO_REF="$default_ref"
    VENDOR_HARNESS_TO=""
else
    [[ -z "$HARNESS_REPO_REF" ]] && HARNESS_REPO_REF="$VENDOR_HARNESS_TO"
fi

# 兼底：可选字段填 <未配置>
for v in TEST_COMMAND LINT_COMMAND; do
    if [[ -z "${!v}" ]]; then printf -v "$v" '%s' "$UNCONFIGURED"; fi
done
[[ -z "$HARNESS_REPO_REF" ]] && { echo "错误：HARNESS_REPO_REF 不能为空" >&2; exit 1; }

# ----------------------------------------------------------------------------
# 上下文（全局变量供 lib 使用）
# ----------------------------------------------------------------------------
declare -A REPLACEMENTS=(
    [TEST_COMMAND]="$TEST_COMMAND"
    [LINT_COMMAND]="$LINT_COMMAND"
    [HARNESS_REPO_REF]="$HARNESS_REPO_REF"
    [HARNESS_VERSION]="$HARNESS_VERSION"
)
# 派生占位符：从 .github/ 子目录链接回 vendor 时需多一级 ../；URL 则保持原样
if [[ "$HARNESS_REPO_REF" =~ ^(https?://|/) ]]; then
    REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]="$HARNESS_REPO_REF"
else
    REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]="../$HARNESS_REPO_REF"
fi
# VENDOR_DIR：被 vendor 文档与 .github/ 模板引用 vendor 目录时使用；NoVendor 模式下无意义但保持非空避免破坏路径结构
if [[ -n "$VENDOR_HARNESS_TO" ]]; then
    REPLACEMENTS[VENDOR_DIR]="$VENDOR_HARNESS_TO"
else
    REPLACEMENTS[VENDOR_DIR]=".he"
fi

declare -A SELECTIONS
[[ -n "$COPILOT_AGENTS" ]] && SELECTIONS["copilot/custom-agents"]="$COPILOT_AGENTS"

# 总结 + 确认
echo
echo '==> 即将使用以下占位符渲染 / Rendering with placeholders:'
UNCONFIGURED_COUNT=0
for key in TEST_COMMAND LINT_COMMAND HARNESS_REPO_REF; do
    val="${REPLACEMENTS[$key]}"
    printf '    %-20s = %s\n' "$key" "$val"
    [[ "$val" == "$UNCONFIGURED" ]] && UNCONFIGURED_COUNT=$((UNCONFIGURED_COUNT + 1))
done
if [[ $UNCONFIGURED_COUNT -gt 0 ]]; then
    echo
    echo "    [!] 有 $UNCONFIGURED_COUNT 项未配置，将渲染为 $UNCONFIGURED / $UNCONFIGURED_COUNT placeholder(s) unset:"
    echo "        grep -RFn '$UNCONFIGURED' '$TARGET_REPO/.github'"
fi

if [[ $NON_INTERACTIVE -eq 0 ]]; then
    echo
    read -r -p '继续？ / Proceed? [Y/n]: ' confirm
    case "${confirm,,}" in
        n|no) echo '已取消 / Cancelled.'; exit 1 ;;
    esac
fi

# ----------------------------------------------------------------------------
# 逐个执行 target（vendor 由 target.json 中的 single/tree render 自行处理）
# ----------------------------------------------------------------------------
for t in "${TARGETS_ARR[@]}"; do
    invoke_target "$INTEGRATIONS_ROOT/$t" "$TARGET_REPO"
done

# ----------------------------------------------------------------------------
# 写 manifest
# ----------------------------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
    # manifest 永远落 vendor 目录；NoVendor 模式下退回 .he/（仅放 manifest，不放文档）
    manifest_dir="$TARGET_REPO/${VENDOR_HARNESS_TO:-.he}"
    manifest_path="$manifest_dir/manifest.json"
    mkdir -p "$manifest_dir"

    harness_commit=""
    if command -v git >/dev/null 2>&1; then
        harness_commit=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "")
    fi

    # 合并：旧 manifest 中的 entry 若本次未出现则保留
    declare -A files_map
    if [[ -f "$manifest_path" ]]; then
        while IFS=$'\t' read -r kind sha path; do
            [[ -z "$path" ]] && continue
            files_map["$path"]="$kind|$sha"
        done < <(jq -r '.files[]? | [.kind, .sha256, .path] | @tsv' "$manifest_path" 2>/dev/null || true)
    fi
    if [[ -f "$MANIFEST_TMP" ]]; then
        while IFS=$'\t' read -r kind sha path; do
            [[ -z "$path" ]] && continue
            files_map["$path"]="$kind|$sha"
        done <"$MANIFEST_TMP"
    fi

    targets_json=$(printf '%s\n' "${TARGETS_ARR[@]}" | jq -R . | jq -s .)
    files_json='[]'
    for path in $(printf '%s\n' "${!files_map[@]}" | sort); do
        IFS='|' read -r kind sha <<<"${files_map[$path]}"
        files_json=$(jq --arg p "$path" --arg s "$sha" --arg k "$kind" \
            '. += [{path:$p, sha256:$s, kind:$k}]' <<<"$files_json")
    done

    jq -n \
        --arg version "$HARNESS_VERSION" \
        --arg commit  "$harness_commit" \
        --arg ts      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg vendor  "$VENDOR_HARNESS_TO" \
        --argjson targets "$targets_json" \
        --argjson files   "$files_json" \
        --arg tc  "$TEST_COMMAND" \
        --arg lc  "$LINT_COMMAND" \
        --arg hr  "$HARNESS_REPO_REF" \
        '{schema:"v1", harness_version:$version, harness_commit:$commit, installed_at:$ts, targets:$targets, vendor_dir:$vendor, replacements:{TEST_COMMAND:$tc, LINT_COMMAND:$lc, HARNESS_REPO_REF:$hr}, files:$files}' \
        >"$manifest_path"

    echo
    echo "==> 已写入 manifest / Manifest written: $manifest_path"

    # ----------------------------------------------------------------------------
    # install.log（每次 install / uninstall 追加一行，作为变更审计来源）
    # ----------------------------------------------------------------------------
    rendered_count=0; vendored_count=0; total_count=0
    if [[ -f "$MANIFEST_TMP" ]]; then
        rendered_count=$(awk -F'\t' '$1=="rendered"{c++} END{print c+0}' "$MANIFEST_TMP")
        vendored_count=$(awk -F'\t' '$1=="vendored"{c++} END{print c+0}' "$MANIFEST_TMP")
        total_count=$(awk 'END{print NR+0}' "$MANIFEST_TMP")
    fi
    log_path="$manifest_dir/install.log"
    ts_iso=$(date '+%Y-%m-%dT%H:%M:%S%z')
    commit_tag=${harness_commit:-unknown}
    targets_tag=$(IFS=,; echo "${TARGETS_ARR[*]}")
    printf '[%s] install · harness@%s · targets=%s · files=%d (rendered=%d, vendored=%d)\n' \
        "$ts_iso" "$commit_tag" "$targets_tag" "$total_count" "$rendered_count" "$vendored_count" \
        >>"$log_path"
fi
[[ -n "$MANIFEST_TMP" && -f "$MANIFEST_TMP" ]] && rm -f "$MANIFEST_TMP"

# ----------------------------------------------------------------------------
# 完成
# ----------------------------------------------------------------------------
echo
if [[ $DRY_RUN -eq 1 ]]; then
    echo "DryRun 完成，未写入任何文件 / DryRun done, nothing written."
else
    echo "完成。下一步建议 / Done. Suggested next steps:"
    echo "  1. cd $TARGET_REPO"
    [[ -n "$VENDOR_HARNESS_TO" ]] && echo "  2. git status $VENDOR_HARNESS_TO"
    echo "  3. git diff 检查修改是否符合预期 / inspect changes"
    echo "  4. 检查残留占位符 / scan for unrendered placeholders: grep -rn '{{' '$TARGET_REPO/.github' 2>/dev/null"
fi
