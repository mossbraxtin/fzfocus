#!/bin/bash
# db.sh — SQLite helpers for fzfocus

DB_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/fzfocus/fzfocus.db"

db_init() {
    mkdir -p "$(dirname "$DB_FILE")"
    sqlite3 "$DB_FILE" <<'SQL'
CREATE TABLE IF NOT EXISTS todos (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL,
    description TEXT,
    due_date    TEXT,
    priority    TEXT    DEFAULT 'none',
    status      TEXT    DEFAULT 'pending',
    tags        TEXT,
    linked_note TEXT
);
SQL
}

db_query() {
    sqlite3 "$DB_FILE" "$1"
}

db_exec() {
    sqlite3 "$DB_FILE" "$1"
}

# Usage: db_todo_add "title" "desc" "due_date" "priority" "tags"
db_todo_add() {
    local title="$1" desc="$2" due="$3" priority="${4:-none}" tags="$5"
    db_exec "INSERT INTO todos (title, description, due_date, priority, tags)
             VALUES ('$(db_escape "$title")', '$(db_escape "$desc")', '$(db_escape "$due")', '$(db_escape "$priority")', '$(db_escape "$tags")');"
}

db_todo_done() {
    local id="$1"
    local current
    current=$(db_query "SELECT status FROM todos WHERE id=$id;")
    if [[ $current == "done" ]]; then
        db_exec "UPDATE todos SET status='pending' WHERE id=$id;"
    else
        db_exec "UPDATE todos SET status='done' WHERE id=$id;"
    fi
}

db_todo_delete() {
    db_exec "DELETE FROM todos WHERE id=$1;"
}

db_todo_priority_cycle() {
    local id="$1"
    local current
    current=$(db_query "SELECT priority FROM todos WHERE id=$id;")
    local next
    case "$current" in
        none) next="low" ;;
        low)  next="med" ;;
        med)  next="high" ;;
        high) next="none" ;;
        *)    next="none" ;;
    esac
    db_exec "UPDATE todos SET priority='$next' WHERE id=$id;"
}

db_todo_link_note() {
    local id="$1" note="$2"
    db_exec "UPDATE todos SET linked_note='$(db_escape "$note")' WHERE id=$id;"
}

db_escape() {
    echo "${1//\'/\'\'}"
}
