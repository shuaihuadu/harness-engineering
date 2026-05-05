#!/usr/bin/env bash
# Harness Engineering · 多工具集成统一入口（bash 端）
#
# 用法：
#   ./install.sh --target-repo /path/to/repo [--targets copilot,claude-code] \
#                [--project-name X] [--primary-language C#] ...
#
# 依赖：bash 4+，jq

set -euo pipefail

# ----------------------------------------------------------------------------
# 参数
# ----------------------------------------------------------------------------
TARGET_REPO=""
TARGETS="copilot"
PROJECT_NAME=""
PROJECT_ONE_LINER=""
PRIMARY_LANGUAGE=""
TECH_STACK=""
TEST_COMMAND=""
LINT_COMMAND=""
HARNESS_REPO_REF=""
VENDOR_HARNESS_TO=".harness-engineering"
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
        --project-name)       PROJECT_NAME="$2";       shift 2 ;;
        --project-one-liner)  PROJECT_ONE_LINER="$2";  shift 2 ;;
        --primary-language)   PRIMARY_LANGUAGE="$2";   shift 2 ;;
        --tech-stack)         TECH_STACK="$2";         shift 2 ;;
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
    [[ -f "$INTEGRATIONS_ROOT/$t/target.json" ]] || { echo "未知 target：$t（在 $INTEGRATIONS_ROOT 下未找到 $t/target.json）" >&2; exit 1; }
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
PRIOR_MANIFEST_PATH="$TARGET_REPO/.harness-engineering/manifest.json"
PRIOR_VERSION=""
if [[ -f "$PRIOR_MANIFEST_PATH" ]]; then
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

echo
echo "==> Harness Engineering v$HARNESS_VERSION · 集成同步 / Integration sync"
echo "    目标仓库 / Target repo : $TARGET_REPO"
echo "    安装目标 / Targets     : $TARGETS"
echo "    交互模式 / Interactive : $([[ $NON_INTERACTIVE -eq 1 ]] && echo '否 / no' || echo '是 / yes')"

if [[ -n "$DETECTED_PROJECT_NAME$DETECTED_PRIMARY_LANGUAGE$DETECTED_TECH_STACK$DETECTED_TEST_COMMAND$DETECTED_LINT_COMMAND" ]]; then
    echo
    echo '    自动探测 / Auto-detected:'
    [[ -n "$DETECTED_PROJECT_NAME"     ]] && echo "      ProjectName     = $DETECTED_PROJECT_NAME"
    [[ -n "$DETECTED_PRIMARY_LANGUAGE" ]] && echo "      PrimaryLanguage = $DETECTED_PRIMARY_LANGUAGE"
    [[ -n "$DETECTED_TECH_STACK"       ]] && echo "      TechStack       = $DETECTED_TECH_STACK"
    [[ -n "$DETECTED_TEST_COMMAND"     ]] && echo "      TestCommand     = $DETECTED_TEST_COMMAND"
    [[ -n "$DETECTED_LINT_COMMAND"     ]] && echo "      LintCommand     = $DETECTED_LINT_COMMAND"
fi
if [[ ${#PRIOR[@]} -gt 0 ]]; then
    echo
    echo "    检测到上次 manifest（v$PRIOR_VERSION），将作为默认值预填 / Detected previous manifest, prefilling defaults"
fi
echo

resolve_placeholder PROJECT_NAME      'PROJECT_NAME'      "$DETECTED_PROJECT_NAME"     '项目名称 / Project name (PROJECT_NAME)'
resolve_placeholder PROJECT_ONE_LINER 'PROJECT_ONE_LINER' ''                           '一句话定位 / One-liner pitch (PROJECT_ONE_LINER, optional)'
resolve_placeholder PRIMARY_LANGUAGE  'PRIMARY_LANGUAGE'  "$DETECTED_PRIMARY_LANGUAGE" '主语言 / Primary language (PRIMARY_LANGUAGE)'
resolve_placeholder TECH_STACK        'TECH_STACK'        "$DETECTED_TECH_STACK"       '技术栈 / Tech stack (TECH_STACK)'
resolve_placeholder TEST_COMMAND      'TEST_COMMAND'      "$DETECTED_TEST_COMMAND"     '测试命令 / Test command (TEST_COMMAND)'
resolve_placeholder LINT_COMMAND      'LINT_COMMAND'      "$DETECTED_LINT_COMMAND"     '代码风格检查命令 / Lint command (LINT_COMMAND)'

# Vendor 目录：CLI 显式传入 > 上次 manifest.vendor_dir > 默认 .harness-engineering
if [[ $NO_VENDOR -eq 0 && $VENDOR_HARNESS_TO_EXPLICIT -eq 0 ]]; then
    vendor_default="$VENDOR_HARNESS_TO"
    if [[ -f "$PRIOR_MANIFEST_PATH" ]]; then
        prior_vendor=$(jq -r '.vendor_dir // ""' "$PRIOR_MANIFEST_PATH" 2>/dev/null || echo "")
        [[ -n "$prior_vendor" ]] && vendor_default="$prior_vendor"
    fi
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

# 兼底 + 可选字段填 <未配置>
[[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="$(basename "$TARGET_REPO")"
for v in PROJECT_ONE_LINER PRIMARY_LANGUAGE TECH_STACK TEST_COMMAND LINT_COMMAND; do
    if [[ -z "${!v}" ]]; then printf -v "$v" '%s' "$UNCONFIGURED"; fi
done
[[ -z "$HARNESS_REPO_REF" ]] && { echo "错误：HARNESS_REPO_REF 不能为空" >&2; exit 1; }

# ----------------------------------------------------------------------------
# 上下文（全局变量供 lib 使用）
# ----------------------------------------------------------------------------
declare -A REPLACEMENTS=(
    [PROJECT_NAME]="$PROJECT_NAME"
    [PROJECT_ONE_LINER]="$PROJECT_ONE_LINER"
    [PRIMARY_LANGUAGE]="$PRIMARY_LANGUAGE"
    [TECH_STACK]="$TECH_STACK"
    [TEST_COMMAND]="$TEST_COMMAND"
    [LINT_COMMAND]="$LINT_COMMAND"
    [HARNESS_REPO_REF]="$HARNESS_REPO_REF"
)
# 派生占位符：从 .github/ 子目录链接回 vendor 时需多一级 ../；URL 则保持原样
if [[ "$HARNESS_REPO_REF" =~ ^(https?://|/) ]]; then
    REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]="$HARNESS_REPO_REF"
else
    REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]="../$HARNESS_REPO_REF"
fi

declare -A SELECTIONS
[[ -n "$COPILOT_AGENTS" ]] && SELECTIONS["copilot/custom-agents"]="$COPILOT_AGENTS"

# 总结 + 确认
echo
echo '==> 即将使用以下占位符渲染 / Rendering with placeholders:'
UNCONFIGURED_COUNT=0
for key in PROJECT_NAME PROJECT_ONE_LINER PRIMARY_LANGUAGE TECH_STACK TEST_COMMAND LINT_COMMAND HARNESS_REPO_REF; do
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
# Vendor
# ----------------------------------------------------------------------------
if [[ -n "$VENDOR_HARNESS_TO" ]]; then
    vendor_abs="$TARGET_REPO/$VENDOR_HARNESS_TO"
    echo
    echo "==> Vendor 规范文档 / Vendor harness docs -> $vendor_abs"
    sync_vendored_tree "$REPO_ROOT" "$vendor_abs" agents docs templates README.md
else
    echo
    echo "==> 跳过 vendor / Skipping vendor (--no-vendor)"
fi

# ----------------------------------------------------------------------------
# 逐个执行 target
# ----------------------------------------------------------------------------
for t in "${TARGETS_ARR[@]}"; do
    invoke_target "$INTEGRATIONS_ROOT/$t" "$TARGET_REPO"
done

# ----------------------------------------------------------------------------
# 写 manifest
# ----------------------------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
    manifest_dir="$TARGET_REPO/.harness-engineering"
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
        --arg pn  "$PROJECT_NAME" \
        --arg pol "$PROJECT_ONE_LINER" \
        --arg pl  "$PRIMARY_LANGUAGE" \
        --arg ts2 "$TECH_STACK" \
        --arg tc  "$TEST_COMMAND" \
        --arg lc  "$LINT_COMMAND" \
        --arg hr  "$HARNESS_REPO_REF" \
        '{schema:"v1", harness_version:$version, harness_commit:$commit, installed_at:$ts, targets:$targets, vendor_dir:$vendor, replacements:{PROJECT_NAME:$pn, PROJECT_ONE_LINER:$pol, PRIMARY_LANGUAGE:$pl, TECH_STACK:$ts2, TEST_COMMAND:$tc, LINT_COMMAND:$lc, HARNESS_REPO_REF:$hr}, files:$files}' \
        >"$manifest_path"

    echo
    echo "==> 已写入 manifest / Manifest written: $manifest_path"
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
