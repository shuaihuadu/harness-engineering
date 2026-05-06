#!/usr/bin/env bash
# Harness Engineering · 通用同步引擎（bash 端，target-agnostic）
#
# 上下文以全局变量传入：
#   FORCE / NO_DELETE / DRY_RUN / OVERWRITE_ALL / DELETE_ALL  (0/1)
#   TARGET_REPO          采用方仓库根（绝对路径，用于 manifest 相对路径）
#   MANIFEST_TMP         可选；若设置则把 entry 以 "kind\tsha256\tpath" 追加进去
# 占位符以关联数组 REPLACEMENTS 传入（key 不带 {{}}）
#
# 公开函数：
#   sync_rendered_file <source> <destination>
#   sync_vendored_tree <source_root> <target_root> <items...>
#   sync_render_orphans <source_dir> <destination_dir> <source_glob> <target_glob>

set -euo pipefail

# ----------------------------------------------------------------------------
# Manifest 追踪（可选；MANIFEST_TMP 未设置时静默跳过）
# ----------------------------------------------------------------------------
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "错误：缺少 sha256sum / shasum" >&2; exit 1
    fi
}

add_manifest_entry() {
    # $1=abs_path  $2=canonical_file（用来算 sha；通常是已落盘文件，或临时渲染产物）  $3=kind
    local abs="$1" canonical="$2" kind="$3"
    [[ -z "${MANIFEST_TMP:-}" ]] && return 0
    [[ -z "${TARGET_REPO:-}" ]] && return 0
    local rel="${abs#$TARGET_REPO/}"
    local hash; hash=$(sha256_of "$canonical")
    printf '%s\t%s\t%s\n' "$kind" "$hash" "$rel" >>"$MANIFEST_TMP"
}

# ----------------------------------------------------------------------------
# 占位符
# ----------------------------------------------------------------------------
render_placeholders() {
    # stdin -> stdout
    local sed_args=()
    for key in "${!REPLACEMENTS[@]}"; do
        local value="${REPLACEMENTS[$key]}"
        # 转义 sed 替换字符
        local escaped
        escaped=$(printf '%s' "$value" | sed -e 's/[\/&|]/\\&/g')
        sed_args+=( -e "s|{{${key}}}|${escaped}|g" )
    done
    sed "${sed_args[@]}"
}

# ----------------------------------------------------------------------------
# 字节比较
# ----------------------------------------------------------------------------
files_equal() {
    local a="$1" b="$2"
    [[ -f "$a" && -f "$b" ]] && cmp -s "$a" "$b"
}

# ----------------------------------------------------------------------------
# 交互决策
# ----------------------------------------------------------------------------
ask_conflict() {
    # 0=overwrite 1=keep 2=abort
    local path="$1" kind="$2"
    if [[ $FORCE -eq 1 ]]; then return 0; fi
    if [[ $OVERWRITE_ALL -eq 1 ]]; then return 0; fi
    if [[ ${NON_INTERACTIVE:-0} -eq 1 ]]; then return 1; fi
    echo
    echo "  ! 冲突：$kind 内容与现有文件不一致"
    echo "    $path"
    while true; do
        read -r -p "    [O]verwrite / [K]eep / [A]ll-overwrite / a[B]ort: " ans
        case "${ans,,}" in
            o) return 0 ;;
            k) return 1 ;;
            a) OVERWRITE_ALL=1; return 0 ;;
            b) return 2 ;;
            *) echo "    请输入 O / K / A / B" ;;
        esac
    done
}

ask_delete() {
    # 0=delete 1=keep 2=abort
    local path="$1"
    if [[ $NO_DELETE -eq 1 ]]; then return 1; fi
    if [[ $FORCE -eq 1 ]]; then return 0; fi
    if [[ $DELETE_ALL -eq 1 ]]; then return 0; fi
    if [[ ${NON_INTERACTIVE:-0} -eq 1 ]]; then return 1; fi
    echo
    echo "  ! 孤儿：源已删除，但目标仍存在"
    echo "    $path"
    while true; do
        read -r -p "    [D]elete / [K]eep / [A]ll-delete / a[B]ort: " ans
        case "${ans,,}" in
            d) return 0 ;;
            k) return 1 ;;
            a) DELETE_ALL=1; return 0 ;;
            b) return 2 ;;
            *) echo "    请输入 D / K / A / B" ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# 写文件（UTF-8 NoBOM）
# ----------------------------------------------------------------------------
write_file() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat >"$path"
}

# ----------------------------------------------------------------------------
# 同步单个渲染文件
# ----------------------------------------------------------------------------
sync_rendered_file() {
    local source="$1" destination="$2"
    [[ -f "$source" ]] || { echo "错误：source 不存在 $source" >&2; exit 1; }

    # 按目标文件深度动态计算 HARNESS_REPO_REF_FROM_GITHUB
    local _saved_link="${REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]:-}"
    local _ref="${REPLACEMENTS[HARNESS_REPO_REF]:-}"
    if [[ -n "$_ref" ]]; then
        if [[ "$_ref" =~ ^(https?://|/) ]]; then
            REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]="$_ref"
        else
            local _dest_dir; _dest_dir=$(dirname "$destination")
            local _rel="${_dest_dir#$TARGET_REPO}"
            _rel="${_rel#/}"
            local _depth=0
            if [[ -n "$_rel" ]]; then
                # shellcheck disable=SC2206
                local _parts=( ${_rel//\// } )
                _depth=${#_parts[@]}
            fi
            local _prefix=""
            local _i
            for (( _i=0; _i<_depth; _i++ )); do _prefix+='../'; done
            REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]="${_prefix}${_ref}"
        fi
    fi

    local tmp; tmp=$(mktemp)
    render_placeholders <"$source" >"$tmp"

    # 还原（避免泄露给后续 vendor 文件）
    if [[ -n "$_saved_link" ]]; then
        REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]="$_saved_link"
    else
        unset 'REPLACEMENTS[HARNESS_REPO_REF_FROM_GITHUB]'
    fi

    if [[ -f "$destination" ]] && cmp -s "$destination" "$tmp"; then
        echo "   skip   $destination (unchanged)"
        add_manifest_entry "$destination" "$tmp" 'rendered'
        rm -f "$tmp"; return 0
    fi

    if [[ -f "$destination" ]]; then
        set +e; ask_conflict "$destination" 'render'; local d=$?; set -e
        case $d in
            1) echo "   keep   $destination"; add_manifest_entry "$destination" "$tmp" 'rendered'; rm -f "$tmp"; return 0 ;;
            2) rm -f "$tmp"; echo "用户中止" >&2; exit 1 ;;
        esac
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "   dryrun $destination"
        add_manifest_entry "$destination" "$tmp" 'rendered'
    else
        mkdir -p "$(dirname "$destination")"
        cp "$tmp" "$destination"
        echo "   write  $destination"
        add_manifest_entry "$destination" "$tmp" 'rendered'
    fi
    rm -f "$tmp"
}

# ----------------------------------------------------------------------------
# 同步 vendor 目录树
# ----------------------------------------------------------------------------
sync_vendored_tree() {
    local source_root="$1"; shift
    local target_root="$1"; shift
    local items=( "$@" )

    declare -A src_map
    declare -A tgt_map

    for item in "${items[@]}"; do
        local sp="$source_root/$item"
        if [[ -f "$sp" ]]; then
            src_map["$item"]="$sp"
        elif [[ -d "$sp" ]]; then
            while IFS= read -r f; do
                local rel="${f#$source_root/}"
                # 排除 sync-engine 的输入产物（仅供渲染，不应进 vendor）
                local base; base=$(basename "$f")
                case "$base" in
                    *.template.md|*.skeleton.md|target.json) continue ;;
                esac
                src_map["$rel"]="$f"
            done < <(find "$sp" -type f)
        fi
        local tp="$target_root/$item"
        if [[ -f "$tp" ]]; then
            tgt_map["$item"]="$tp"
        elif [[ -d "$tp" ]]; then
            while IFS= read -r f; do
                local rel="${f#$target_root/}"
                tgt_map["$rel"]="$f"
            done < <(find "$tp" -type f)
        fi
    done

    # 孤儿
    local orphans=()
    for rel in "${!tgt_map[@]}"; do
        [[ -z "${src_map[$rel]+x}" ]] && orphans+=( "$rel" )
    done

    echo "   分类：源 ${#src_map[@]} 个文件 / 目标 ${#tgt_map[@]} 个文件 / 孤儿 ${#orphans[@]} 个"

    # 同步
    for rel in $(printf '%s\n' "${!src_map[@]}" | sort); do
        local src="${src_map[$rel]}"
        local dst="$target_root/$rel"

        if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
            add_manifest_entry "$dst" "$src" 'vendored'
            continue
        fi

        if [[ -f "$dst" ]]; then
            set +e; ask_conflict "$dst" 'vendor'; local d=$?; set -e
            case $d in
                1) echo "   keep   $dst"; add_manifest_entry "$dst" "$src" 'vendored'; continue ;;
                2) echo "用户中止" >&2; exit 1 ;;
            esac
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            echo "   dryrun $dst"
        else
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
            echo "   sync   $dst"
        fi
        add_manifest_entry "$dst" "$src" 'vendored'
    done

    # 删除孤儿
    for rel in $(printf '%s\n' "${orphans[@]:-}" | sort); do
        [[ -z "$rel" ]] && continue
        local dst="${tgt_map[$rel]}"
        set +e; ask_delete "$dst"; local d=$?; set -e
        case $d in
            0)
                if [[ $DRY_RUN -eq 1 ]]; then
                    echo "   dryrun-delete $dst"
                else
                    rm -f "$dst"
                    echo "   delete $dst"
                fi
                ;;
            1) echo "   keep   $dst (orphan)" ;;
            2) echo "用户中止" >&2; exit 1 ;;
        esac
    done

    # 清空目录
    if [[ $DRY_RUN -eq 0 ]]; then
        for item in "${items[@]}"; do
            local p="$target_root/$item"
            [[ -d "$p" ]] && find "$p" -type d -empty -delete 2>/dev/null || true
        done
    fi
}

# ----------------------------------------------------------------------------
# Render 目录的孤儿检测
# ----------------------------------------------------------------------------
sync_render_orphans() {
    local source_dir="$1" destination_dir="$2" source_glob="$3" target_glob="$4"
    [[ -d "$destination_dir" ]] || return 0

    declare -A expected
    if [[ -d "$source_dir" ]]; then
        for f in "$source_dir"/$source_glob; do
            [[ -f "$f" ]] || continue
            local name; name=$(basename "$f")
            local dest_name="${name/.template/}"
            expected["$dest_name"]=1
        done
    fi

    for f in "$destination_dir"/$target_glob; do
        [[ -f "$f" ]] || continue
        local name; name=$(basename "$f")
        [[ -n "${expected[$name]+x}" ]] && continue
        set +e; ask_delete "$f"; local d=$?; set -e
        case $d in
            0)
                if [[ $DRY_RUN -eq 1 ]]; then
                    echo "   dryrun-delete $f"
                else
                    rm -f "$f"
                    echo "   delete $f"
                fi
                ;;
            1) echo "   keep   $f (orphan)" ;;
            2) echo "用户中止" >&2; exit 1 ;;
        esac
    done
}
