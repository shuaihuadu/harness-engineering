#!/usr/bin/env bash
# Harness Engineering · 卸载脚本（基于 manifest）
#
# 用法：
#   ./uninstall.sh --target-repo /path/to/repo [--force] [--dry-run]
#
# 安全策略：
#   - 必须存在 <target-repo>/.harness-engineering/manifest.json，否则报错
#   - 文件已不存在 → 跳过（幂等）
#   - 文件 sha256 与 manifest 一致 → 默认删除
#   - 文件 sha256 不一致 → 默认保留并告警；--force 才删
#   - 自下而上清理空目录；非空目录绝不递归删
#
# 依赖：bash 4+，jq，sha256sum 或 shasum

set -euo pipefail

TARGET_REPO=""
FORCE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-repo) TARGET_REPO="$2"; shift 2 ;;
        --force)       FORCE=1;          shift ;;
        --dry-run)     DRY_RUN=1;        shift ;;
        -h|--help)     sed -n '4,12p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

[[ -z "$TARGET_REPO" ]] && { echo "错误：必须指定 --target-repo" >&2; exit 2; }
[[ ! -d "$TARGET_REPO" ]] && { echo "错误：目录不存在：$TARGET_REPO" >&2; exit 1; }
TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "错误：本脚本依赖 jq" >&2; exit 1; }

manifest_dir="$TARGET_REPO/.harness-engineering"
manifest_path="$manifest_dir/manifest.json"

[[ -f "$manifest_path" ]] || { echo "未发现 harness-engineering 安装记录：$manifest_path" >&2; exit 1; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "错误：缺少 sha256sum / shasum" >&2; exit 1
    fi
}

version=$(jq -r '.harness_version // "unknown"' "$manifest_path")
commit=$(jq -r '.harness_commit // "unknown"' "$manifest_path")
total=$(jq '.files | length' "$manifest_path")

echo
echo "==> Harness Engineering · 卸载"
echo "    目标仓库：$TARGET_REPO"
echo "    manifest 版本：$version（commit: $commit）"
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
    rm -f "$manifest_path"
    echo "   delete .harness-engineering/manifest.json"
    [[ -d "$manifest_dir" && -z "$(ls -A "$manifest_dir" 2>/dev/null)" ]] && {
        rmdir "$manifest_dir"
        echo "   rmdir  .harness-engineering"
    }
    echo
    echo "完成。删除 $deleted / 保留 $kept / 缺失 $missing"
else
    echo
    echo "[!] 以下文件被本地修改过，已保留；manifest 也保留："
    for p in "${modified_kept[@]}"; do echo "    $p"; done
    echo "    若要强制删除：--force；若确认保留请手动删除 manifest 自身。"
    echo
    echo "完成。删除 $deleted / 保留 $kept / 缺失 $missing"
fi
echo
