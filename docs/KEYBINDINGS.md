# HB Perl Keyboard Shortcuts

This reference lists all keyboard shortcuts available in the GTK3 GUI (`hb_gui`).

---

## Global

| Shortcut | Action |
|---|---|
| `Ctrl+Q` | Quit HB Perl |
| `F1` | Open Help / About dialog |
| `Ctrl+,` | Open Preferences dialog |

---

## File Menu

| Shortcut | Action |
|---|---|
| `Ctrl+N` | New file (open a blank editor tab) |
| `Ctrl+O` | Open file |
| `Ctrl+S` | Save current file |
| `Ctrl+Shift+S` | Save As |
| `Ctrl+W` | Close current editor tab |

---

## Edit Menu

| Shortcut | Action |
|---|---|
| `Ctrl+Z` | Undo |
| `Ctrl+Y` / `Ctrl+Shift+Z` | Redo |
| `Ctrl+X` | Cut |
| `Ctrl+C` | Copy |
| `Ctrl+V` | Paste |
| `Ctrl+A` | Select All |
| `Ctrl+F` | Find |
| `Ctrl+H` | Find & Replace |
| `Ctrl+G` | Go to Line |

---

## Code Actions

| Shortcut | Action |
|---|---|
| `F5` | Run current script |
| `Ctrl+B` | Build / syntax-check (`perl -c`) |
| `Ctrl+Shift+F` | Format with Perl::Tidy |
| `Ctrl+Shift+L` | Lint with Perl::Critic |
| `Escape` | Stop running script |

---

## Window & View

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+N` | Open a new window (same process) |
| `Ctrl+Tab` | Cycle to next editor tab |
| `Ctrl+Shift+Tab` | Cycle to previous editor tab |
| `Ctrl+1` … `Ctrl+9` | Switch to editor tab N |
| `Ctrl+Shift+E` | Toggle sidebar (script browser) |
| `Ctrl+Shift+T` | Toggle integrated terminal pane |
| `Ctrl+Shift+D` | Toggle dashboard panel |

---

## Script Browser

| Shortcut | Action |
|---|---|
| `Enter` | Run selected script |
| `Ctrl+Enter` | Open selected script in editor |
| `F2` | Rename user script |
| `Delete` | Remove user script (with confirmation) |

---

## Terminal / Output Pane

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+C` | Copy selected text from terminal |
| `Ctrl+Shift+V` | Paste into terminal |
| `Ctrl+L` | Clear output pane |
| `Ctrl+Shift+X` | Export output to file |

---

## CLI Quick Reference

The CLI (`hb_cli`) has no interactive shortcuts, but useful invocations:

```bash
# Run with typo correction ("did you mean?")
hb_cli run sytm_info

# Batch run with JSON export
hb_cli batch --export=json system_info,disk_usage,service_monitor

# Plugin management
hb_cli plugin list
hb_cli plugin disable MyPlugin

# Schedule a script
hb_cli schedule add disk_usage '0 * * * *'
hb_cli schedule list
```

## TUI Quick Reference

Inside the TUI script menu (`hb_tui`):

| Key | Action |
|---|---|
| `1`–`99` | Run the numbered script |
| `/` | Enter search/filter mode |
| `c` | Clear the current filter |
| `b` | Back to the main menu |
| `q` / `Q` | Quit |
