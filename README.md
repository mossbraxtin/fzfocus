# fzfocus

An fzf-based personal info manager for the terminal — calendar, todos, and notes in one keyboard-driven TUI. Navigation powered by [fzf](https://github.com/junegunn/fzf), editing powered by [nvim](https://neovim.io).

## Features

- **Dashboard** — today's todos, upcoming deadlines, and recent notes at a glance
- **Todos** — add, edit, complete, prioritize, and tag todos; link to notes
- **Notes** — create and browse markdown notes with live `bat` previews; open in nvim
- **Calendar** — month grid view with todo indicators; navigate days and add todos by date
- **Vim-style keybindings** throughout (`j`/`k`, `g`/`G`, `/` to search)
- **Plain local data** — markdown files + SQLite; no accounts, no sync, no cloud

## Commands

| Command | Description |
|---|---|
| `fzfocus` | Open dashboard (default) |
| `fzfocus todo` | Browse and manage todos |
| `fzfocus notes` | Browse and edit notes |
| `fzfocus calendar` | Browse calendar by day |

## Key bindings

### All views

| Key | Action |
|---|---|
| `j` / `k` | Navigate down/up |
| `g` / `G` | Jump to top/bottom |
| `ENTER` | Open/edit selected item |
| `ESC` / `q` | Back to dashboard (or quit from dashboard) |
| `ALT-P` | Toggle preview pane |
| `CTRL-D` / `CTRL-U` | Scroll preview half page |

### Dashboard

| Key | Action |
|---|---|
| `t` | Switch to Todos view |
| `n` | Switch to Notes view |
| `c` | Switch to Calendar view |
| `a` | Quick-add todo |
| `/` | Enable fuzzy search |

### Todos

| Key | Action |
|---|---|
| `a` | Add new todo |
| `ENTER` | Edit todo in nvim |
| `d` | Toggle done/pending |
| `D` | Delete todo |
| `p` | Cycle priority (none → low → med → high) |
| `ALT-N` | Open linked note |

### Notes

| Key | Action |
|---|---|
| `a` | New note (opens in nvim) |
| `ENTER` | Open note in nvim |
| `D` | Delete note |
| `r` | Rename note |
| `ALT-T` | Link note to a todo |

### Calendar

| Key | Action |
|---|---|
| `[` / `]` | Previous/next month |
| `a` | Add todo for selected day |
| `ENTER` | View day detail |
| `t` | Switch to Todos view |

## Data

| Path | Contents |
|---|---|
| `~/.local/share/fzfocus/notes/` | Markdown note files |
| `~/.local/share/fzfocus/fzfocus.db` | SQLite database (todos) |
| `~/.config/fzfocus/config` | Config file (sourced at startup) |

## Configuration

`~/.config/fzfocus/config` is a shell file sourced at startup. You can override any of these variables:

```sh
# Override data directory
DATA_DIR="$HOME/.local/share/fzfocus"
NOTES_DIR="$DATA_DIR/notes"
```

## Dependencies

- `fzf`
- `nvim`
- `sqlite3`
- `bat` (previews)

## Installation

### From AUR

```
paru -S fzfocus
```

### Manually

```
sudo install -Dm755 fzfocus /usr/bin/fzfocus
sudo install -Dm644 LICENSE /usr/share/licenses/fzfocus/LICENSE
sudo install -Dm644 README.md /usr/share/doc/fzfocus/README.md
sudo install -Dm644 completions/bash/fzfocus /usr/share/bash-completion/completions/fzfocus
sudo install -Dm644 completions/zsh/_fzfocus /usr/share/zsh/site-functions/_fzfocus
sudo install -Dm644 completions/fish/fzfocus.fish /usr/share/fish/vendor_completions.d/fzfocus.fish
```

Don't forget to install the lib directory alongside the binary or adjust `SCRIPT_DIR` in the main script.

> **Note:** For manual installs, copy `lib/` to `/usr/lib/fzfocus/` and update the `SCRIPT_DIR` line in the `fzfocus` script accordingly.
