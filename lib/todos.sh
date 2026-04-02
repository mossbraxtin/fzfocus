#!/bin/bash
# todos.sh — Todos view for fzfocus

# ── helpers ────────────────────────────────────────────────────────────────────

_todo_priority_color() {
    case "$1" in
        high) echo "\033[1;31m" ;;  # bold red
        med)  echo "\033[1;33m" ;;  # bold yellow
        low)  echo "\033[1;34m" ;;  # bold blue
        *)    echo "\033[0m"    ;;  # reset
    esac
}

_todo_format_list() {
    local today
    today=$(date +%Y-%m-%d)

    db_query "SELECT id, title, due_date, priority, status, tags FROM todos ORDER BY
        CASE status WHEN 'done' THEN 1 ELSE 0 END ASC,
        CASE
            WHEN due_date != '' AND due_date < '$today' THEN 0
            WHEN due_date = '$today' THEN 1
            WHEN due_date != '' THEN 2
            ELSE 3
        END ASC,
        due_date ASC, priority DESC, id ASC;" | while IFS='|' read -r id title due priority status tags; do
        local prefix="" color="" reset="\033[0m" due_label=""

        if [[ $status == "done" ]]; then
            color="\033[2;37m"  # dim gray
            prefix="✓ "
        elif [[ -n $due && $due < $today ]]; then
            color="\033[1;31m"  # bold red (overdue)
            prefix="! "
        elif [[ $due == "$today" ]]; then
            color="\033[1;33m"  # bold yellow (today)
            prefix="▶ "
        else
            color=$(_todo_priority_color "$priority")
            prefix="  "
        fi

        [[ -n $due ]] && due_label=" ($due)"
        local tag_label=""
        [[ -n $tags ]] && tag_label=" [$tags]"

        printf "${color}%s%s%-5s%-40s%s%s${reset}\n" \
            "$prefix" "$id " "" "$title" "$due_label" "$tag_label"
    done
}

_todo_preview() {
    local id="$1"
    db_query "SELECT title, description, due_date, priority, status, tags, linked_note
              FROM todos WHERE id=$id;" | while IFS='|' read -r title desc due priority status tags note; do
        echo -e "\033[1mTitle:\033[0m      $title"
        echo -e "\033[1mStatus:\033[0m     $status"
        echo -e "\033[1mPriority:\033[0m   $priority"
        [[ -n $due ]]  && echo -e "\033[1mDue:\033[0m        $due"
        [[ -n $tags ]] && echo -e "\033[1mTags:\033[0m       $tags"
        [[ -n $note ]] && echo -e "\033[1mNote:\033[0m       $note"
        if [[ -n $desc ]]; then
            echo ""
            echo -e "\033[1mDescription:\033[0m"
            echo "$desc"
        fi
    done
}

_todo_edit_nvim() {
    local id="$1"
    local tmpfile
    tmpfile=$(mktemp /tmp/fzfocus-todo-XXXXXX.md)

    # Write current content to tempfile
    db_query "SELECT title, description, due_date, priority, tags FROM todos WHERE id=$id;" \
        | while IFS='|' read -r title desc due priority tags; do
        cat > "$tmpfile" <<EOF
# $title

due: $due
priority: $priority
tags: $tags

---

$desc
EOF
    done

    nvim "$tmpfile"

    # Parse back: title from first # line, due/priority/tags from front matter, rest is desc
    local new_title new_due new_priority new_tags new_desc
    new_title=$(grep '^# ' "$tmpfile" | head -1 | sed 's/^# //')
    new_due=$(grep '^due:' "$tmpfile" | head -1 | sed 's/^due: *//')
    new_priority=$(grep '^priority:' "$tmpfile" | head -1 | sed 's/^priority: *//')
    new_tags=$(grep '^tags:' "$tmpfile" | head -1 | sed 's/^tags: *//')
    new_desc=$(awk '/^---$/{found++} found==2{print}' "$tmpfile" | tail -n +2)

    db_exec "UPDATE todos SET
        title='$(db_escape "$new_title")',
        description='$(db_escape "$new_desc")',
        due_date='$(db_escape "$new_due")',
        priority='$(db_escape "$new_priority")',
        tags='$(db_escape "$new_tags")'
        WHERE id=$id;"

    rm -f "$tmpfile"
}

_todo_add_prompt() {
    local title due priority tags
    echo -ne "\n\033[1mNew todo\033[0m\n"
    read -r -p "  Title:    " title
    [[ -z $title ]] && return
    read -r -p "  Due date: [YYYY-MM-DD or blank] " due
    read -r -p "  Priority: [none/low/med/high] " priority
    read -r -p "  Tags:     [comma-separated or blank] " tags
    db_todo_add "$title" "" "$due" "${priority:-none}" "$tags"
}

# ── main command ───────────────────────────────────────────────────────────────

cmd_todo() {
    while true; do
        local list
        list=$(_todo_format_list)
        [[ -z $list ]] && list="  (no todos — press 'a' to add one)"

        local FZFOCUS_CMD="$0"
        local selection
        printf '\033[2J\033[H'
        selection=$(echo "$list" | fzf \
            --ansi \
            --disabled \
            --border rounded \
            --border-label ' 󰄬 Todos ' \
            --border-label-pos top \
            --prompt '  Todos › ' \
            --header $'j/k navigate · ENTER edit · a add · d done · D delete · p priority · q back\nalt-n note · alt-f filter' \
            --header-first \
            --preview "$(realpath "$0") --preview-todo \$(echo {} | grep -oP '^\S+\s+\K[0-9]+')" \
            --preview-label ' Detail ' \
            --preview-label-pos 'bottom' \
            --preview-window 'right:45%:wrap:border-left' \
            --bind 'j:down,k:up,g:first,G:last' \
            --bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
            --bind 'ctrl-k:preview-up,ctrl-j:preview-down' \
            --bind 'alt-p:toggle-preview' \
            --bind "q:become(echo __DASHBOARD__)" \
            --bind "esc:become(echo __DASHBOARD__)" \
            --bind "a:become(echo __ADD_TODO__)" \
            --bind "d:become(echo __DONE__{})" \
            --bind "D:become(echo __DELETE__{})" \
            --bind "p:become(echo __PRIORITY__{})" \
            --bind "alt-n:become(echo __OPEN_NOTE__{})" \
            --bind "alt-f:become(echo __FILTER__)" \
            --color 'pointer:yellow,marker:yellow,header:italic:dim,prompt:yellow,hl:yellow,hl+:yellow,border:yellow,label:yellow' \
            --no-multi \
            --expect='enter' \
            2>/dev/null)

        local key line
        key=$(echo "$selection" | head -1)
        line=$(echo "$selection" | tail -1)

        # Extract todo ID from line (second token)
        local id
        id=$(echo "$line" | grep -oP '^\S+\s+\K[0-9]+' 2>/dev/null)

        case "$line" in
            __DASHBOARD__) return ;;
            __ADD_TODO__)
                _todo_add_prompt
                ;;
            __DONE__*)
                [[ -n $id ]] && db_todo_done "$id"
                ;;
            __DELETE__*)
                if [[ -n $id ]]; then
                    local title
                    title=$(db_query "SELECT title FROM todos WHERE id=$id;")
                    read -r -p "Delete '$title'? [y/N] " confirm
                    [[ $confirm =~ ^[Yy]$ ]] && db_todo_delete "$id"
                fi
                ;;
            __PRIORITY__*)
                [[ -n $id ]] && db_todo_priority_cycle "$id"
                ;;
            __OPEN_NOTE__*)
                if [[ -n $id ]]; then
                    local note
                    note=$(db_query "SELECT linked_note FROM todos WHERE id=$id;")
                    if [[ -n $note ]]; then
                        nvim "$NOTES_DIR/$note"
                    else
                        echo "No linked note."
                        sleep 1
                    fi
                fi
                ;;
            __FILTER__)
                read -r -p "Filter by tag: " tag
                # Relaunch with filter — for now just continue loop
                ;;
            *)
                if [[ $key == "enter" && -n $id ]]; then
                    _todo_edit_nvim "$id"
                fi
                ;;
        esac
    done
}
