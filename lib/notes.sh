#!/bin/bash
# notes.sh — Notes view for fzfocus

_notes_list() {
    # List notes sorted by modification time (newest first)
    if [[ -d $NOTES_DIR ]]; then
        find "$NOTES_DIR" -maxdepth 1 -name '*.md' -printf '%T@ %f\n' 2>/dev/null \
            | sort -rn \
            | awk '{print $2}'
    fi
}

_note_title() {
    local file="$1"
    # Use first # heading if present, else filename without extension
    local heading
    heading=$(grep -m1 '^# ' "$NOTES_DIR/$file" 2>/dev/null | sed 's/^# //')
    if [[ -n $heading ]]; then
        echo "$heading"
    else
        echo "${file%.md}"
    fi
}

_notes_format_list() {
    _notes_list | while read -r file; do
        local title modified
        title=$(_note_title "$file")
        modified=$(date -r "$NOTES_DIR/$file" '+%Y-%m-%d' 2>/dev/null)
        printf "%-40s  \033[2;37m%s  %s\033[0m\n" "$title" "$modified" "$file"
    done
}

_note_filename_from_line() {
    # Extract the filename (last whitespace-separated token) from a formatted list line
    echo "$1" | awk '{print $NF}'
}

_note_new() {
    local title
    read -r -p "  Note title: " title
    [[ -z $title ]] && return

    # Slugify title → filename
    local slug
    slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
    local file="${slug}.md"
    local fullpath="$NOTES_DIR/$file"

    # If file already exists, append a counter
    local counter=1
    while [[ -f $fullpath ]]; do
        file="${slug}-${counter}.md"
        fullpath="$NOTES_DIR/$file"
        ((counter++))
    done

    mkdir -p "$NOTES_DIR"
    printf '# %s\n\n' "$title" > "$fullpath"
    nvim "$fullpath"
}

_note_rename() {
    local file="$1"
    local old_title
    old_title=$(_note_title "$file")
    read -r -p "  Rename '$old_title' to: " new_title
    [[ -z $new_title ]] && return

    local new_slug
    new_slug=$(echo "$new_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
    local new_file="${new_slug}.md"

    mv "$NOTES_DIR/$file" "$NOTES_DIR/$new_file"

    # Update any todos that linked to the old filename
    db_exec "UPDATE todos SET linked_note='$(db_escape "$new_file")' WHERE linked_note='$(db_escape "$file")';"
}

_note_link_todo() {
    local file="$1"
    local todo_list
    todo_list=$(db_query "SELECT id, title FROM todos WHERE status='pending' ORDER BY id;")
    [[ -z $todo_list ]] && echo "No pending todos." && sleep 1 && return

    local selected
    selected=$(echo "$todo_list" | fzf \
        --prompt ' Link to todo > ' \
        --with-nth='2..' \
        --delimiter='|' \
        --color 'pointer:cyan,prompt:cyan' \
        2>/dev/null)

    local todo_id
    todo_id=$(echo "$selected" | cut -d'|' -f1)
    [[ -n $todo_id ]] && db_todo_link_note "$todo_id" "$file"
}

# ── main command ───────────────────────────────────────────────────────────────

cmd_notes() {
    while true; do
        local list
        list=$(_notes_format_list)
        [[ -z $list ]] && list="  (no notes — press 'a' to create one)"

        local selection
        selection=$(echo "$list" | fzf \
            --ansi \
            --disabled \
            --prompt ' Notes > ' \
            --header $'j/k: navigate  ENTER: open  a: new  D: delete  r: rename  q: back\n ALT-t: link todo  ALT-d: date info' \
            --preview "awk '{print \$NF}' <<< {} | xargs -I{f} bat --color=always --style=plain '$NOTES_DIR/{f}' 2>/dev/null || echo '(empty)'" \
            --preview-label ' Note Preview ' \
            --preview-label-pos 'bottom' \
            --preview-window 'right:55%:wrap' \
            --bind 'j:down,k:up,g:first,G:last' \
            --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up' \
            --bind 'alt-k:preview-up,alt-j:preview-down' \
            --bind 'alt-p:toggle-preview' \
            --bind "q:become(echo __DASHBOARD__)" \
            --bind "esc:become(echo __DASHBOARD__)" \
            --bind "a:become(echo __NEW_NOTE__)" \
            --bind "D:become(echo __DELETE__{})" \
            --bind "r:become(echo __RENAME__{})" \
            --bind "alt-t:become(echo __LINK_TODO__{})" \
            --bind "alt-d:become(echo __DATE_INFO__{})" \
            --color 'pointer:cyan,marker:cyan,header:italic,prompt:cyan,hl:cyan,hl+:cyan' \
            --no-multi \
            --expect='enter' \
            2>/dev/null)

        local key line
        key=$(echo "$selection" | head -1)
        line=$(echo "$selection" | tail -1)
        local file
        file=$(_note_filename_from_line "$line")

        case "$line" in
            __DASHBOARD__) return ;;
            __NEW_NOTE__)
                _note_new
                ;;
            __DELETE__*)
                if [[ -n $file && -f $NOTES_DIR/$file ]]; then
                    read -r -p "Delete '$file'? [y/N] " confirm
                    [[ $confirm =~ ^[Yy]$ ]] && rm "$NOTES_DIR/$file"
                fi
                ;;
            __RENAME__*)
                [[ -n $file && -f $NOTES_DIR/$file ]] && _note_rename "$file"
                ;;
            __LINK_TODO__*)
                [[ -n $file && -f $NOTES_DIR/$file ]] && _note_link_todo "$file"
                ;;
            __DATE_INFO__*)
                if [[ -n $file && -f $NOTES_DIR/$file ]]; then
                    local created modified
                    created=$(stat -c '%y' "$NOTES_DIR/$file" 2>/dev/null | cut -d' ' -f1)
                    modified=$(date -r "$NOTES_DIR/$file" '+%Y-%m-%d %H:%M' 2>/dev/null)
                    echo -e "\nModified: $modified"
                    sleep 2
                fi
                ;;
            *)
                if [[ $key == "enter" && -n $file && -f $NOTES_DIR/$file ]]; then
                    nvim "$NOTES_DIR/$file"
                fi
                ;;
        esac
    done
}
