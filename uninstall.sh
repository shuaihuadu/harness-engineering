#!/usr/bin/env bash
# Harness Engineering · 卸载脚本（基于 manifest）
#
# 用法：
#   ./uninstall.sh --target-repo /path/to/repo [--vendor-dir <name>] [--force] [--dry-run]
#
# 安全策略：
#   - 优先用 manifest 精确卸载（按 sha256 比对）
#   - 文件已不存在 → 跳过（幂等）
#   - 文件 sha256 与 manifest 一致 → 默认删除
#   - 文件 sha256 不一致 → 默认保留并告警；--force 才删
#   - 自下而上清理空目录；非空目录绝不递归删
#
# Vendor 目录探测顺序（默认 .he/，也可被安装时改为任意名）：
#   1. 显式 --vendor-dir <name>
#   2. 默认 .he/manifest.json
#   3. 掃描顶层一级目录下的 manifest.json（schema==v1）
#
# Manifest 缺失时的兑底（残留清理）：
#   - 例如 install 中途按 Ctrl+C，manifest 还没写入但 vendor 目录
#     或 .github/ 下已经有部分文件落地。
#   - 此时脚本不报错退出，而是启动 best-effort 残留扫描：
#     * 整体清理 <target-repo>/<vendor-dir>/ 目录（纯属本工具产物）
#     * 对 .github/copilot-instructions.md / .github/instructions/*.instructions.md /
#       .github/agents/*.agent.md，仅当文件内含 "Harness Engineering" 标记时才删
#     * 交互模式下会列出候选并请求确认；非交互模式必须显式 --force 才执行删除
#
# 依赖：bash 4+，jq，sha256sum 或 shasum

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

TARGET_REPO=""
FORCE=0
DRY_RUN=0
VENDOR_DIR_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-repo) TARGET_REPO="$2"; shift 2 ;;
        --vendor-dir)  VENDOR_DIR_OVERRIDE="$2"; shift 2 ;;
        --force)       FORCE=1;          shift ;;
        --dry-run)     DRY_RUN=1;        shift ;;
        -h|--help)     sed -n '4,12p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

[[ -z "$TARGET_REPO" ]] && { echo "错误：必须指定 --target-repo" >&2; exit 2; }
[[ ! -d "$TARGET_REPO" ]] && { echo "错误：目录不存在：$TARGET_REPO" >&2; exit 1; }
TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"

# 注意：jq 仅在 manifest 存在的精确卸载路径中需要；best-effort 兜底不依赖 jq。
# 因此把 jq 检查推迟到 manifest 检查之后。

# 定位 vendor 目录：优先显式 --vendor-dir，其次默认 .he/，最后扫描顶层目录
# Locate vendor dir: explicit --vendor-dir > default .he/ > scan top-level dirs
manifest_path=""
manifest_dir=""

if [[ -n "$VENDOR_DIR_OVERRIDE" ]]; then
    manifest_dir="$TARGET_REPO/$VENDOR_DIR_OVERRIDE"
    manifest_path="$manifest_dir/manifest.json"
elif [[ -f "$TARGET_REPO/.he/manifest.json" ]]; then
    manifest_dir="$TARGET_REPO/.he"
    manifest_path="$manifest_dir/manifest.json"
else
    while IFS= read -r -d '' candidate; do
        if command -v jq >/dev/null 2>&1; then
            schema=$(jq -r '.schema // empty' "$candidate" 2>/dev/null || true)
            [[ "$schema" == "v1" ]] || continue
        else
            grep -q '"schema"[[:space:]]*:[[:space:]]*"v1"' "$candidate" 2>/dev/null || continue
        fi
        manifest_path="$candidate"
        manifest_dir="$(dirname "$candidate")"
        break
    done < <(find "$TARGET_REPO" -mindepth 2 -maxdepth 2 -name 'manifest.json' -print0 2>/dev/null)
    # 未找到任何 manifest 时仍以 .he/ 为默认提示路径，交给 best-effort 兜底
    if [[ -z "$manifest_path" ]]; then
        manifest_dir="$TARGET_REPO/.he"
        manifest_path="$manifest_dir/manifest.json"
    fi
fi

vendor_rel="${manifest_dir#$TARGET_REPO/}"

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "错误：缺少 sha256sum / shasum" >&2; exit 1
    fi
}

# 已渲染产物始终包含 "Harness Engineering" 字面量；用作残留清理的归属标记。
has_harness_marker() {
    local p="$1"
    [[ -f "$p" ]] || return 1
    grep -qE 'Harness Engineering|harness-engineering' "$p" 2>/dev/null
}

# Manifest 缺失时的兜底：扫描已知路径并清理残留
best_effort_cleanup() {
    echo
    echo "[!] 未发现 manifest.json：$manifest_path" >&2
    echo "    安装可能在写入 manifest 前被中断（如 Ctrl+C）。" >&2
    echo "    启动 best-effort 残留扫描 / Best-effort residual scan。" >&2

    local -a cand_kinds=()    # dir | file
    local -a cand_paths=()    # 绝对路径
    local -a cand_rels=()     # 相对路径（用于显示）
    local -a cand_safe=()     # 1=安全 0=需 --force

    if [[ -d "$manifest_dir" ]]; then
        cand_kinds+=( "dir" )
        cand_paths+=( "$manifest_dir" )
        cand_rels+=( "$vendor_rel/" )
        cand_safe+=( 1 )
    fi

    local -a known_files=(".github/copilot-instructions.md")
    if [[ -d "$TARGET_REPO/.github/instructions" ]]; then
        while IFS= read -r -d '' f; do
            known_files+=( ".github/instructions/$(basename "$f")" )
        done < <(find "$TARGET_REPO/.github/instructions" -maxdepth 1 -name '*.instructions.md' -print0 2>/dev/null)
    fi
    if [[ -d "$TARGET_REPO/.github/agents" ]]; then
        while IFS= read -r -d '' f; do
            known_files+=( ".github/agents/$(basename "$f")" )
        done < <(find "$TARGET_REPO/.github/agents" -maxdepth 1 -name '*.agent.md' -print0 2>/dev/null)
    fi

    # 去重
    local -A seen=()
    local -a uniq_files=()
    for r in "${known_files[@]}"; do
        [[ -n "${seen[$r]:-}" ]] && continue
        seen[$r]=1
        uniq_files+=( "$r" )
    done

    for rel in "${uniq_files[@]}"; do
        local abs="$TARGET_REPO/$rel"
        [[ -f "$abs" ]] || continue
        cand_kinds+=( "file" )
        cand_paths+=( "$abs" )
        cand_rels+=( "$rel" )
        if has_harness_marker "$abs"; then
            cand_safe+=( 1 )
        else
            cand_safe+=( 0 )
        fi
    done

    if [[ ${#cand_kinds[@]} -eq 0 ]]; then
        echo
        echo "    未发现任何残留 / No residual files found."
        return 0
    fi

    echo
    echo "    候选 / Candidates:"
    local i
    for ((i=0; i<${#cand_kinds[@]}; i++)); do
        local reason
        if [[ "${cand_kinds[$i]}" == "dir" ]]; then
            reason="整目录（本工具专属）"
        elif [[ ${cand_safe[$i]} -eq 1 ]]; then
            reason="含 Harness 标记 ✓"
        else
            reason="无标记 (需 --force)"
        fi
        printf "      [%-4s] %-55s %s\n" "${cand_kinds[$i]}" "${cand_rels[$i]}" "$reason"
    done

    # 交互判定：DryRun → 仅预览；--force → 直接执行；交互 TTY → 询问；否则仅预览
    local proceed=0
    if [[ $DRY_RUN -eq 1 ]]; then
        proceed=0
    elif [[ $FORCE -eq 1 ]]; then
        proceed=1
    elif [[ -t 0 ]]; then
        echo
        read -r -p "继续删除上述候选？/ Proceed? [y/N] " ans
        case "${ans,,}" in
            y|yes) proceed=1 ;;
            *)     proceed=0 ;;
        esac
    else
        echo
        echo "    非交互模式且未传 --force：仅预览，不执行删除。"
        echo "    Non-interactive without --force: preview only."
    fi

    local deleted=0
    local kept=0
    for ((i=0; i<${#cand_kinds[@]}; i++)); do
        local rel="${cand_rels[$i]}"
        local abs="${cand_paths[$i]}"
        local safe="${cand_safe[$i]}"
        local should_delete=0
        if [[ $safe -eq 1 || $FORCE -eq 1 ]]; then should_delete=1; fi
        if [[ $should_delete -eq 0 ]]; then
            echo "   keep   $rel (无 Harness 标记，使用 --force 强制删除)"
            kept=$((kept + 1))
            continue
        fi
        if [[ $DRY_RUN -eq 1 || $proceed -eq 0 ]]; then
            echo "   dryrun-delete $rel"
            continue
        fi
        if [[ "${cand_kinds[$i]}" == "dir" ]]; then
            rm -rf "$abs"
            echo "   delete $rel (recursive)"
        else
            rm -f "$abs"
            echo "   delete $rel"
            local parent
            parent=$(dirname "$abs")
            while [[ -d "$parent" && "$parent" != "$TARGET_REPO" && "$parent" == "$TARGET_REPO"/* ]]; do
                if [[ -z "$(ls -A "$parent" 2>/dev/null)" ]]; then
                    rmdir "$parent"
                    echo "   rmdir  $parent"
                    parent=$(dirname "$parent")
                else
                    break
                fi
            done
        fi
        deleted=$((deleted + 1))
    done

    echo
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "DryRun 完成（best-effort）。预计删除 $((${#cand_kinds[@]} - kept)) / 保留 $kept"
    elif [[ $proceed -eq 0 ]]; then
        echo "已取消（未删除任何文件）/ Cancelled (nothing removed)."
    else
        echo "完成（best-effort）。删除 $deleted / 保留 $kept"
    fi
    return 0
}

if [[ ! -f "$manifest_path" ]]; then
    best_effort_cleanup
    echo
    exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "错误：本脚本依赖 jq（用于解析 manifest.json）" >&2; exit 1; }

version=$(jq -r '.harness_version // "unknown"' "$manifest_path")
commit=$(jq -r '.harness_commit // "unknown"' "$manifest_path")
total=$(jq '.files | length' "$manifest_path")

echo
echo "==> Harness Engineering · 卸载"
echo "    目标仓库：$TARGET_REPO"
echo "    manifest 版本：${version}（commit: ${commit}）"
echo "    待处理文件数：$total"
echo

deleted=0; skipped=0; kept=0; missing=0
modified_kept=()
declare -A touched_dirs

while IFS=$'\t' read -r path expected_sha; do
    [[ -z "$path" ]] && continue
    abs="$TARGET_REPO/$path"

    if [[ ! -f "$abs" ]]; then
        echo "   miss   $path (已不存在)"
        missing=$((missing + 1))
        continue
    fi

    cur_sha=$(sha256_of "$abs")
    if [[ "$cur_sha" != "$expected_sha" && $FORCE -eq 0 ]]; then
        echo "   keep   $path (本地已修改，使用 --force 强制删除)"
        modified_kept+=( "$path" )
        kept=$((kept + 1))
        continue
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "   dryrun-delete $path"
    else
        rm -f "$abs"
        echo "   delete $path"
    fi
    deleted=$((deleted + 1))
    parent=$(dirname "$abs")
    touched_dirs["$parent"]=1
done < <(jq -r '.files[]? | [.path, .sha256] | @tsv' "$manifest_path")

# 清理空目录（自下而上）
if [[ $DRY_RUN -eq 0 ]]; then
    for dir in $(printf '%s\n' "${!touched_dirs[@]}" | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-); do
        cur="$dir"
        while [[ -d "$cur" && "$cur" != "$TARGET_REPO" && "$cur" == "$TARGET_REPO"/* ]]; do
            if [[ -z "$(ls -A "$cur" 2>/dev/null)" ]]; then
                rmdir "$cur"
                echo "   rmdir  $cur"
                cur=$(dirname "$cur")
            else
                break
            fi
        done
    done
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo
    echo "DryRun 完成。删除 $deleted / 保留 $kept / 缺失 $missing"
elif [[ ${#modified_kept[@]} -eq 0 ]]; then
    # 写一行 uninstall 记录到 install.log（与 install.sh 复用同一审计日志）
    if [[ -d "$manifest_dir" ]]; then
        log_path="$manifest_dir/install.log"
        ts_iso=$(date '+%Y-%m-%dT%H:%M:%S%z')
        commit_tag="${commit:-unknown}"
        printf '[%s] uninstall · harness@%s · deleted=%d · kept=%d · missing=%d\n' \
            "$ts_iso" "$commit_tag" "$deleted" "$kept" "$missing" >>"$log_path"
    fi

    rm -f "$manifest_path"
    echo "   delete $vendor_rel/manifest.json"
    # install.log 是审计日志、不在 manifest 里；clean uninstall 时一并移除以让目录归零
    if [[ -f "$log_path" ]]; then
        rm -f "$log_path"
        echo "   delete $vendor_rel/install.log"
    fi
    [[ -d "$manifest_dir" && -z "$(ls -A "$manifest_dir" 2>/dev/null)" ]] && {
        rmdir "$manifest_dir"
        echo "   rmdir  $vendor_rel"
    }
    echo
    echo "完成。删除 $deleted / 保留 $kept / 缺失 $missing"
else
    # 写一行 uninstall 记录到 install.log（即便有保留项也要留审计）
    if [[ -d "$manifest_dir" ]]; then
        log_path="$manifest_dir/install.log"
        ts_iso=$(date '+%Y-%m-%dT%H:%M:%S%z')
        commit_tag="${commit:-unknown}"
        printf '[%s] uninstall · harness@%s · deleted=%d · kept=%d · missing=%d\n' \
            "$ts_iso" "$commit_tag" "$deleted" "$kept" "$missing" >>"$log_path"
    fi

    echo
    echo "[!] 以下文件被本地修改过，已保留；manifest 与 install.log 也保留："
    for p in "${modified_kept[@]}"; do echo "    $p"; done
    echo "    若要强制删除：--force；若确认保留请手动删除 manifest 自身。"
    echo
    echo "完成。删除 $deleted / 保留 $kept / 缺失 $missing"
fi
echo
