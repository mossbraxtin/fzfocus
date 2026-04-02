#!/bin/bash
# dashboard.sh — Dashboard (default view) for fzfocus

_dash_build_list() {
    local today
    today=$(date +%Y-%m-%d)
    local next_week
    next_week=$(date -d '+7 days' +%Y-%m-%d)

    # ── Section: Today's todos ─────────────────────────────────────────────────
    local today_todos
    today_todos=$(db_query "SELECT id, title, priority, status FROM todos
        WHERE due_date='$today' ORDER BY status ASC, priority DESC;")

    local overdue_todos
    overdue_todos=$(db_query "SELECT id, title, priority, due_date FROM todos
        WHERE due_date < '$today' AND due_date != '' AND status='pending'
        ORDER BY due_date ASC;")

    local upcoming_todos
    upcoming_todos=$(db_query "SELECT id, title, priority, due_date FROM todos
        WHERE due_date > '$today' AND due_date <= '$next_week' AND status='pending'
        ORDER BY due_date ASC;")

    local recent_notes
    if [[ -d $NOTES_DIR ]]; then
        recent_notes=$(find "$NOTES_DIR" -maxdepth 1 -name '*.md' -printf '%T@ %f\n' 2>/dev/null \
            | sort -rn | head -5 | awk '{print $2}')
    fi

    # ── Overdue ────────────────────────────────────────────────────────────────
    if [[ -n $overdue_todos ]]; then
        echo -e "\033[1;31m  OVERDUE\033[0m"
        echo "$overdue_todos" | while IFS='|' read -r id title priority due; do
            printf "\033[0;31m  ✗ %-40s %s\033[0m  todo:%s\n" "$title" "$due" "$id"
        done
        echo ""
    fi

    # ── Today ──────────────────────────────────────────────────────────────────
    echo -e "\033[1;33m  TODAY — $(date '+%A, %B %-d')\033[0m"
    if [[ -n $today_todos ]]; then
        echo "$today_todos" | while IFS='|' read -r id title priority status; do
            local mark=" "
            local color="\033[0;33m"
            [[ $status == "done" ]] && mark="✓" && color="\033[2;37m"
            printf "${color}  [%s] %-40s\033[0m  todo:%s\n" "$mark" "$title" "$id"
        done
    else
        echo -e "\033[2;37m  (nothing due today)\033[0m"
    fi
    echo ""

    # ── Upcoming ───────────────────────────────────────────────────────────────
    if [[ -n $upcoming_todos ]]; then
        echo -e "\033[1;36m  UPCOMING (next 7 days)\033[0m"
        echo "$upcoming_todos" | while IFS='|' read -r id title priority due; do
            local weekday
            weekday=$(date -d "$due" '+%a')
            printf "\033[0;36m  ○ %-40s %s %s\033[0m  todo:%s\n" "$title" "$weekday" "$due" "$id"
        done
        echo ""
    fi

    # ── Recent Notes ───────────────────────────────────────────────────────────
    if [[ -n $recent_notes ]]; then
        echo -e "\033[1;35m  RECENT NOTES\033[0m"
        echo "$recent_notes" | while read -r file; do
            local title
            title=$(grep -m1 '^# ' "$NOTES_DIR/$file" 2>/dev/null | sed 's/^# //')
            [[ -z $title ]] && title="${file%.md}"
            local modified
            modified=$(date -r "$NOTES_DIR/$file" '+%Y-%m-%d' 2>/dev/null)
            printf "\033[0;35m  ▷ %-40s %s\033[0m  note:%s\n" "$title" "$modified" "$file"
        done
        echo ""
    fi
}

_dash_preview_item() {
    local item="$1"
    local type ref
    type=$(echo "$item" | grep -oP '(todo|note)(?=:)')
    ref=$(echo "$item" | grep -oP '(?<=(todo|note):)\S+')

    case "$type" in
        todo)
            _todo_preview "$ref"
            ;;
        note)
            bat --color=always --style=plain "$NOTES_DIR/$ref" 2>/dev/null || echo "(empty)"
            ;;
        *)
            echo "$item"
            ;;
    esac
}

_dash_open_item() {
    local item="$1"
    local type ref
    type=$(echo "$item" | grep -oP '(todo|note)(?=:)')
    ref=$(echo "$item" | grep -oP '(?<=(todo|note):)\S+')

    case "$type" in
        todo)
            _todo_edit_nvim "$ref"
            ;;
        note)
            nvim "$NOTES_DIR/$ref"
            ;;
    esac
}

# ── main command ───────────────────────────────────────────────────────────────

cmd_dashboard() {
    while true; do
        local list
        list=$(_dash_build_list)

        local selection
        selection=$(echo "$list" | fzf \
            --ansi \
            --disabled \
            --prompt ' fzfocus > ' \
            --header $'j/k: navigate  t: todos  n: notes  c: calendar  a: add todo  /: search  q: quit' \
            --preview "$(realpath "$0") --preview-dash {}" \
            --preview-label ' Detail ' \
            --preview-label-pos 'bottom' \
            --preview-window 'right:45%:wrap' \
            --bind 'j:down,k:up,g:first,G:last' \
            --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up' \
            --bind 'alt-k:preview-up,alt-j:preview-down' \
            --bind 'alt-p:toggle-preview' \
            --bind "/:enable-search" \
            --bind "t:become(echo __TODOS__)" \
            --bind "n:become(echo __NOTES__)" \
            --bind "c:become(echo __CALENDAR__)" \
            --bind "a:become(echo __ADD_TODO__)" \
            --bind "q:become(echo __QUIT__)" \
            --bind "esc:become(echo __QUIT__)" \
            --color 'pointer:magenta,marker:magenta,header:italic,prompt:magenta,hl:magenta,hl+:magenta' \
            --no-multi \
            --expect='enter' \
            2>/dev/null)

        local key line
        key=$(echo "$selection" | head -1)
        line=$(echo "$selection" | tail -1)

        case "$line" in
            __QUIT__)     exit 0 ;;
            __TODOS__)    cmd_todo ;;
            __NOTES__)    cmd_notes ;;
            __CALENDAR__) cmd_calendar ;;
            __ADD_TODO__)
                _todo_add_prompt
                ;;
            *)
                if [[ $key == "enter" ]]; then
                    _dash_open_item "$line"
                fi
                ;;
        esac
    done
}
