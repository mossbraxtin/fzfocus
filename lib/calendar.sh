#!/bin/bash
# calendar.sh — Calendar view for fzfocus

# ── ASCII calendar renderer ────────────────────────────────────────────────────

_cal_days_in_month() {
    local year=$1 month=$2
    date -d "$year-$month-01 +1 month -1 day" '+%d'
}

_cal_first_weekday() {
    # Returns 0=Sun..6=Sat for the 1st of given month
    date -d "$1-$2-01" '+%w'
}

_cal_render_month() {
    local year=$1 month=$2
    local today
    today=$(date +%Y-%m-%d)

    local days_in_month first_dow
    days_in_month=$(_cal_days_in_month "$year" "$month")
    first_dow=$(_cal_first_weekday "$year" "$month")

    local month_name
    month_name=$(date -d "$year-$month-01" '+%B %Y')

    echo "  $month_name"
    echo "  Su Mo Tu We Th Fr Sa"

    local line="  "
    local col=$first_dow

    # Pad to first day
    for ((i=0; i<first_dow; i++)); do
        line+="   "
    done

    for ((day=1; day<=days_in_month; day++)); do
        local date_str
        printf -v date_str "%04d-%02d-%02d" "$year" "$month" "$day"

        local has_todos
        has_todos=$(db_query "SELECT COUNT(*) FROM todos WHERE due_date='$date_str' AND status='pending';")

        local day_fmt
        printf -v day_fmt "%2d" "$day"

        if [[ $date_str == "$today" ]]; then
            day_fmt="\033[1;33m${day_fmt}\033[0m"
        elif [[ ${has_todos:-0} -gt 0 ]]; then
            day_fmt="\033[1;36m${day_fmt}\033[0m"
        fi

        line+="${day_fmt} "
        ((col++))

        if ((col % 7 == 0)); then
            echo -e "$line"
            line="  "
        fi
    done

    [[ $line != "  " ]] && echo -e "$line"
}

# Returns fzf-list entries: one per day in the month
_cal_day_entries() {
    local year=$1 month=$2
    local days_in_month
    days_in_month=$(_cal_days_in_month "$year" "$month")
    local today
    today=$(date +%Y-%m-%d)

    for ((day=1; day<=days_in_month; day++)); do
        local date_str
        printf -v date_str "%04d-%02d-%02d" "$year" "$month" "$day"
        local weekday
        weekday=$(date -d "$date_str" '+%a')

        local has_todos
        has_todos=$(db_query "SELECT COUNT(*) FROM todos WHERE due_date='$date_str' AND status='pending';")

        local indicator=""
        [[ ${has_todos:-0} -gt 0 ]] && indicator=" ●"
        [[ $date_str == "$today" ]] && indicator+=" ◀ today"

        local color=""
        local reset="\033[0m"
        [[ $date_str == "$today" ]] && color="\033[1;33m"
        [[ ${has_todos:-0} -gt 0 && $date_str != "$today" ]] && color="\033[1;36m"

        printf "${color}%s  %s%s${reset}\n" "$date_str" "$weekday" "$indicator"
    done
}

_cal_preview_day() {
    local date_str="$1"
    echo -e "\033[1m$(date -d "$date_str" '+%A, %B %-d %Y')\033[0m"
    echo ""

    local todos
    todos=$(db_query "SELECT id, title, priority, status FROM todos WHERE due_date='$date_str' ORDER BY status ASC, priority DESC;")

    if [[ -n $todos ]]; then
        echo -e "\033[1mTodos:\033[0m"
        echo "$todos" | while IFS='|' read -r id title priority status; do
            local mark="[ ]"
            [[ $status == "done" ]] && mark="[✓]"
            local pcolor=""
            case "$priority" in
                high) pcolor="\033[1;31m" ;;
                med)  pcolor="\033[1;33m" ;;
                low)  pcolor="\033[1;34m" ;;
            esac
            echo -e "  ${pcolor}${mark} ${title}\033[0m"
        done
    else
        echo "  (no todos)"
    fi
}

_cal_add_for_day() {
    local date_str="$1"
    echo -ne "\n\033[1mNew todo for $date_str\033[0m\n"
    local title priority tags
    read -r -p "  Title:    " title
    [[ -z $title ]] && return
    read -r -p "  Priority: [none/low/med/high] " priority
    read -r -p "  Tags:     [comma-separated or blank] " tags
    db_todo_add "$title" "" "$date_str" "${priority:-none}" "$tags"
}

# ── main command ───────────────────────────────────────────────────────────────

cmd_calendar() {
    local year month
    year=$(date +%Y)
    month=$(date +%m)

    while true; do
        local list
        list=$(_cal_day_entries "$year" "$month")

        local month_header
        month_header=$(_cal_render_month "$year" "$month")

        printf '\033[2J\033[H'
        local selection
        selection=$(echo "$list" | fzf \
            --ansi \
            --disabled \
            --border rounded \
            --border-label " 󰃮 $(date -d "$year-$month-01" '+%B %Y') " \
            --border-label-pos top \
            --prompt '  Calendar › ' \
            --header $'j/k navigate · [/] prev/next month · ENTER day detail · a add todo · q back' \
            --header-first \
            --preview "$(realpath "$0") --preview-day {1}" \
            --preview-label ' Day ' \
            --preview-label-pos 'bottom' \
            --preview-window 'right:45%:wrap:border-left' \
            --bind 'j:down,k:up,g:first,G:last' \
            --bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
            --bind 'ctrl-k:preview-up,ctrl-j:preview-down' \
            --bind 'alt-p:toggle-preview' \
            --bind "q:become(echo __DASHBOARD__)" \
            --bind "esc:become(echo __DASHBOARD__)" \
            --bind "a:become(echo __ADD__{})" \
            --bind "t:become(echo __TODOS__)" \
            --bind "[:become(echo __PREV_MONTH__)" \
            --bind "]:become(echo __NEXT_MONTH__)" \
            --color 'pointer:blue,marker:blue,header:italic:dim,prompt:blue,hl:blue,hl+:blue,border:blue,label:blue' \
            --no-multi \
            --expect='enter' \
            2>/dev/null)

        local key line
        key=$(echo "$selection" | head -1)
        line=$(echo "$selection" | tail -1)
        local date_str
        date_str=$(echo "$line" | awk '{print $1}')

        case "$line" in
            __DASHBOARD__) return ;;
            __TODOS__)     cmd_todo; return ;;
            __PREV_MONTH__)
                if ((month == 1)); then month=12; ((year--)); else ((month--)); fi
                printf -v month "%02d" "$month"
                ;;
            __NEXT_MONTH__)
                if ((month == 12)); then month=1; ((year++)); else ((month++)); fi
                printf -v month "%02d" "$month"
                ;;
            __ADD__*)
                [[ -n $date_str ]] && _cal_add_for_day "$date_str"
                ;;
            *)
                if [[ $key == "enter" && -n $date_str ]]; then
                    # Show day detail in a simple preview
                    clear
                    _cal_preview_day "$date_str"
                    echo ""
                    read -r -p "Press any key to return..." -n1
                fi
                ;;
        esac
    done
}
