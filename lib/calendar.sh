#!/bin/bash
# calendar.sh - Calendar view for fzfocus

_cal_days_in_month() {
    date -d "$1-$2-01 +1 month -1 day" '+%d'
}

_cal_first_weekday() {
    date -d "$1-$2-01" '+%w'
}

# Render ASCII month grid, highlighting selected date
_cal_render_grid() {
    local year=$1 month=$2 selected=${3:-}
    local today
    today=$(date +%Y-%m-%d)

    local days_in_month first_dow
    days_in_month=$(_cal_days_in_month "$year" "$month")
    first_dow=$(_cal_first_weekday "$year" "$month")

    printf '\033[1;37m  %-20s\033[0m\n' "$(date -d "$year-$month-01" '+%B %Y')"
    printf '\033[2;37m  Su  Mo  Tu  We  Th  Fr  Sa\033[0m\n'

    local line="  "
    local col=$first_dow

    for ((i=0; i<first_dow; i++)); do
        line+="    "
    done

    for ((day=1; day<=days_in_month; day++)); do
        local date_str
        printf -v date_str "%04d-%02d-%02d" "$year" "$month" "$day"

        local has_todos
        has_todos=$(db_query "SELECT COUNT(*) FROM todos WHERE due_date='$date_str' AND status='pending';")

        local day_fmt dot open close
        printf -v day_fmt "%2d" "$day"
        dot=" "
        [[ ${has_todos:-0} -gt 0 ]] && dot="·"

        if [[ $date_str == "$selected" && $date_str == "$today" ]]; then
            open='\033[1;7;33m'; close='\033[0m'
        elif [[ $date_str == "$selected" ]]; then
            open='\033[1;7;34m'; close='\033[0m'
        elif [[ $date_str == "$today" ]]; then
            open='\033[1;33m';   close='\033[0m'
        elif [[ ${has_todos:-0} -gt 0 ]]; then
            open='\033[1;36m';   close='\033[0m'
        else
            open='\033[0;37m';   close='\033[0m'
        fi

        line+="${open}${day_fmt}${dot}${close} "
        ((col++))

        if ((col % 7 == 0)); then
            printf "%b\n" "$line"
            line="  "
        fi
    done

    [[ $line != "  " ]] && printf "%b\n" "$line"
    echo ""
    printf '\033[2;37m  \033[1;33m■\033[0;2;37m today  \033[0;1;36m■\033[0;2;37m has todos  \033[1;7;34m · \033[0;2;37m selected\033[0m\n'
}

# Returns fzf-list entries: one per day in the month
_cal_day_entries() {
    local year=$1 month=$2
    local days_in_month
    days_in_month=$(_cal_days_in_month "$year" "$month")
    local today
    today=$(date +%Y-%m-%d)

    for ((day=1; day<=days_in_month; day++)); do
        local date_str weekday has_todos indicator color reset="\033[0m"
        printf -v date_str "%04d-%02d-%02d" "$year" "$month" "$day"
        weekday=$(date -d "$date_str" '+%a')
        has_todos=$(db_query "SELECT COUNT(*) FROM todos WHERE due_date='$date_str' AND status='pending';")

        indicator=""
        [[ ${has_todos:-0} -gt 0 ]] && indicator=" ●"

        color="\033[0;37m"
        [[ $date_str == "$today" ]]                            && color="\033[1;33m" && indicator+=" ◀ today"
        [[ ${has_todos:-0} -gt 0 && $date_str != "$today" ]]  && color="\033[1;36m"

        printf "${color}%s  %s%s${reset}\n" "$date_str" "$weekday" "$indicator"
    done
}

_cal_preview_grid() {
    local selected="$1" year="$2" month="$3"
    db_init
    _cal_render_grid "$year" "$month" "$selected"
    echo ""
    _cal_preview_day "$selected"
}

_cal_preview_day() {
    local date_str="$1"
    [[ -z $date_str || ! $date_str =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && return

    printf '\033[1m%s\033[0m\n' "$(date -d "$date_str" '+%A, %B %-d %Y')"
    echo ""

    local todos
    todos=$(db_query "SELECT id, title, priority, status FROM todos WHERE due_date='$date_str' ORDER BY status ASC, priority DESC;")

    if [[ -n $todos ]]; then
        echo "$todos" | while IFS='|' read -r id title priority status; do
            local mark="[ ]"
            [[ $status == "done" ]] && mark="[✓]"
            local pcolor="\033[0m"
            case "$priority" in
                high) pcolor="\033[1;31m" ;;
                med)  pcolor="\033[1;33m" ;;
                low)  pcolor="\033[1;34m" ;;
            esac
            printf "  ${pcolor}%s %s\033[0m\n" "$mark" "$title"
        done
    else
        printf '\033[2;37m  (no todos)\033[0m\n'
    fi
}

_cal_add_for_day() {
    local date_str="$1"
    printf '\n\033[1mNew todo for %s\033[0m\n' "$date_str"
    local title priority tags
    read -r -p "  Title:    " title
    [[ -z $title ]] && return
    read -r -p "  Priority: [none/low/med/high] " priority
    read -r -p "  Tags:     [comma-separated or blank] " tags
    db_todo_add "$title" "" "$date_str" "${priority:-none}" "$tags"
}

cmd_calendar() {
    local year month
    year=$(date +%Y)
    month=$(date +%m)

    while true; do
        local list
        list=$(_cal_day_entries "$year" "$month")

        printf '\033[2J\033[H'
        local selection
        selection=$(echo "$list" | fzf \
            --ansi \
            --disabled \
            --border rounded \
            --border-label " $(date -d "$year-$month-01" '+%B %Y') " \
            --border-label-pos top \
            --prompt '  Calendar > ' \
            --header $'j/k navigate  [/] prev/next month  a add todo  q back' \
            --header-first \
            --preview "$FZFOCUS_SCRIPT --preview-cal-grid {1} $year $month" \
            --preview-label ' Grid + Day ' \
            --preview-label-pos bottom \
            --preview-window 'right:32:wrap:border-left:noscroll' \
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
                if ((10#$month == 1)); then month=12; ((year--)); else printf -v month "%02d" "$((10#$month - 1))"; fi
                ;;
            __NEXT_MONTH__)
                if ((10#$month == 12)); then month=01; ((year++)); else printf -v month "%02d" "$((10#$month + 1))"; fi
                ;;
            __ADD__*)
                [[ $date_str =~ ^[0-9]{4} ]] && _cal_add_for_day "$date_str"
                ;;
            *)
                if [[ $key == "enter" && $date_str =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                    clear
                    _cal_preview_day "$date_str"
                    echo ""
                    read -r -p "Press any key to return..." -n1
                fi
                ;;
        esac
    done
}
