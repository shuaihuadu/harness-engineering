#!/usr/bin/env bash
# Harness Engineering · Target 调度器（bash 端）
# 读取 target.json 并按声明执行渲染。依赖：jq

set -euo pipefail

# ----------------------------------------------------------------------------
# 选择映射：SELECTIONS["target/source_dir"] = "stem1,stem2" 或 "all"
# 由顶层入口填充
# ----------------------------------------------------------------------------

read_target_spec() {
    local target_dir="$1"
    local json_path="$target_dir/target.json"
    [[ -f "$json_path" ]] || { echo "未找到 target 清单：$json_path" >&2; exit 1; }
    cat "$json_path"
}

invoke_target() {
    local target_dir="$1" target_repo="$2"
    local spec; spec=$(read_target_spec "$target_dir")
    local name; name=$(jq -r '.name' <<<"$spec")
    local display; display=$(jq -r '.display' <<<"$spec")

    echo
    echo "==> [$display] 开始同步"

    local total; total=$(jq '.renders | length' <<<"$spec")
    local idx=0

    while IFS= read -r render; do
        idx=$((idx + 1))
        local kind; kind=$(jq -r '.kind' <<<"$render")
        echo
        echo "[$idx/$total · $name · $kind]"

        case "$kind" in
            single)    invoke_render_single "$render" "$target_dir" "$target_repo" ;;
            directory) invoke_render_directory "$render" "$target_dir" "$target_repo" "$name" ;;
            *) echo "不支持的 render kind：$kind" >&2; exit 1 ;;
        esac
    done < <(jq -c '.renders[]' <<<"$spec")
}

invoke_render_single() {
    local render="$1" target_dir="$2" target_repo="$3"
    local source; source=$(jq -r '.source' <<<"$render")
    local target; target=$(jq -r '.target' <<<"$render")
    sync_rendered_file "$target_dir/$source" "$target_repo/$target"
}

# 交互菜单：列出 source_dir 中的可选模板让用户挑
# Interactive menu: list templates from source_dir for user to pick
# args: $1=src_dir $2=source_glob $3=default_select_csv $4=group_name
# stdout: 返回 csv（'all' / '' / 'stem1,stem2'）—— 注意所有提示输出走 stderr
read_selectable_menu() {
    local src_dir="$1" source_glob="$2" default_csv="$3" group="$4"

    # 收集所有 stem
    local stems=()
    for f in "$src_dir"/$source_glob; do
        [[ -f "$f" ]] || continue
        local n; n=$(basename "$f")
        local stem="${n/.template/}"; stem="${stem%.*}"
        # 再去掉一层（例如 commit-auditor.agent → commit-auditor）：保留首段
        stem="${stem%%.*}"
        stems+=("$stem")
    done

    if [[ ${#stems[@]} -eq 0 ]]; then
        echo ""
        return 0
    fi

    # 默认标签
    local default_label
    if [[ ",$default_csv," == *",all,"* ]]; then
        default_label="all"
    elif [[ -z "$default_csv" ]]; then
        default_label="none"
    else
        default_label="$default_csv"
    fi

    {
        echo
        echo "   ?  $group 可选项 / available items:"
        local i=0
        for stem in "${stems[@]}"; do
            i=$((i + 1))
            printf "        [%d] %s\n" "$i" "$stem"
        done
        echo "      输入编号（1,3）/ stem 名 / all / none，回车采纳默认"
        echo "      Enter numbers (e.g. 1,3) / stem names / all / none; press Enter for default"
    } >&2

    local answer
    read -r -p "      选择 / Choose [$default_label]: " answer </dev/tty

    if [[ -z "$answer" ]]; then
        echo "$default_csv"
        return 0
    fi
    local lc; lc="$(echo "$answer" | tr '[:upper:]' '[:lower:]' | xargs)"
    if [[ "$lc" == "all" ]]; then echo "all"; return 0; fi
    if [[ "$lc" == "none" || "$lc" == "no" || "$lc" == "n" || "$lc" == "0" || "$lc" == "-" || "$lc" == "skip" ]]; then
        echo ""
        return 0
    fi

    # 解析数字 / stem 混合
    IFS=$', \t' read -ra parts <<<"$lc"
    local picked=()
    for p in "${parts[@]}"; do
        [[ -z "$p" ]] && continue
        if [[ "$p" =~ ^[0-9]+$ ]]; then
            local idx="$p"
            if (( idx >= 1 && idx <= ${#stems[@]} )); then
                picked+=("${stems[$((idx - 1))]}")
            else
                echo "无效编号 / invalid index: $p" >&2
            fi
        else
            local found=0
            for s in "${stems[@]}"; do
                if [[ "$s" == "$p" ]]; then picked+=("$p"); found=1; break; fi
            done
            [[ $found -eq 0 ]] && echo "未找到模板 / unknown stem: $p" >&2
        fi
    done

    # 去重
    local seen=()
    local unique=()
    for x in "${picked[@]}"; do
        local dup=0
        for y in "${seen[@]}"; do [[ "$y" == "$x" ]] && dup=1 && break; done
        [[ $dup -eq 0 ]] && { seen+=("$x"); unique+=("$x"); }
    done
    (IFS=,; echo "${unique[*]}")
}


invoke_render_directory() {
    local render="$1" target_dir="$2" target_repo="$3" target_name="$4"

    local source_dir; source_dir=$(jq -r '.source_dir' <<<"$render")
    local target_subdir; target_subdir=$(jq -r '.target_dir' <<<"$render")
    local source_glob; source_glob=$(jq -r '.source_glob' <<<"$render")
    local target_glob; target_glob=$(jq -r '.target_glob' <<<"$render")
    local selectable; selectable=$(jq -r '.selectable // false' <<<"$render")
    local orphan_check; orphan_check=$(jq -r '.orphan_check // false' <<<"$render")
    local orphan_only_all; orphan_only_all=$(jq -r '.orphan_check_only_when_all // false' <<<"$render")

    local src_dir="$target_dir/$source_dir"
    local dst_dir="$target_repo/$target_subdir"

    if [[ ! -d "$src_dir" ]]; then
        echo "   skip   $src_dir 不存在"
        return 0
    fi

    # 解析选择
    local picked=""
    local use_all=0
    local has_user_choice=0
    if [[ "$selectable" == "true" ]]; then
        local key1="$target_name/$source_dir"
        if [[ -n "${SELECTIONS[$key1]+x}" ]]; then
            picked="${SELECTIONS[$key1]}"; has_user_choice=1
        elif [[ -n "${SELECTIONS[$target_name]+x}" ]]; then
            picked="${SELECTIONS[$target_name]}"; has_user_choice=1
        fi

        if [[ $has_user_choice -eq 0 ]]; then
            local default_select_csv=""
            local has_field; has_field=$(jq 'has("default_select")' <<<"$render")
            if [[ "$has_field" == "true" ]]; then
                default_select_csv=$(jq -r '.default_select | join(",")' <<<"$render")
            else
                default_select_csv="all"
            fi

            if [[ ${NON_INTERACTIVE:-0} -eq 0 ]]; then
                # 交互菜单 / interactive menu
                picked=$(read_selectable_menu "$src_dir" "$source_glob" "$default_select_csv" "$source_dir")
            else
                picked="$default_select_csv"
            fi
        fi

        if [[ -z "$picked" ]]; then
            echo "   skip   $source_dir：未选择任何项 / nothing selected"
            return 0
        fi

        if [[ ",$picked," == *",all,"* ]]; then use_all=1; fi
    else
        use_all=1
    fi

    # 渲染
    if [[ $use_all -eq 1 ]]; then
        for f in "$src_dir"/$source_glob; do
            [[ -f "$f" ]] || continue
            local name; name=$(basename "$f"); local dest_name="${name/.template/}"
            sync_rendered_file "$f" "$dst_dir/$dest_name"
        done
    else
        IFS=',' read -ra stems <<<"$picked"
        for stem in "${stems[@]}"; do
            local matched=""
            for f in "$src_dir"/$source_glob; do
                [[ -f "$f" ]] || continue
                local name; name=$(basename "$f"); local dest_name="${name/.template/}"
                if [[ "$dest_name" == "$stem".* ]]; then matched="$f"; break; fi
            done
            if [[ -z "$matched" ]]; then
                echo "警告：未找到模板 $stem（in $src_dir）" >&2
                continue
            fi
            local name; name=$(basename "$matched"); local dest_name="${name/.template/}"
            sync_rendered_file "$matched" "$dst_dir/$dest_name"
        done
    fi

    # 孤儿检测
    if [[ "$orphan_check" == "true" ]] && { [[ "$orphan_only_all" != "true" ]] || [[ $use_all -eq 1 ]]; }; then
        sync_render_orphans "$src_dir" "$dst_dir" "$source_glob" "$target_glob"
    fi
}
