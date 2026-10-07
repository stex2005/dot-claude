---
description: Your private todo list (~/.claude/todo.md) — `/todo [list|add|next|done|priority|day|resume] …`; no op lists open items by priority with overdue flagged.
allowed-tools: Read, Write, Edit, Bash(gh *), Bash(git *), Bash(date *), Bash(ls *), Bash(cd *), Bash(python3 *)
argument-hint: "[list|add|next|done|priority|day|resume] [args…]"
---

Follow `~/.claude/docs/todo-format.md`.

Arguments: $ARGUMENTS

**Dispatch on the first word**, then follow that command's file exactly with the remaining arguments:

| Op | Follow | Short form |
|---|---|---|
| `add` | `~/.claude/commands/todo-add.md` | `/todo add "fix box 67 dropoff" --p 1 --due fri` |
| `next` | `~/.claude/commands/todo-next.md` | `/todo next` |
| `done` | `~/.claude/commands/todo-done.md` | `/todo done #4`, `/todo done --check` |
| `priority` | `~/.claude/commands/todo-priority.md` | `/todo priority "A, B, C"` |
| `day` | `~/.claude/commands/todo-day.md` | `/todo day start` / `end` |
| `resume` | `~/.claude/commands/todo-resume.md` | `/todo resume #7`, `/todo resume --link-all` |
| `list`, nothing, or anything else | below | `/todo`, `/todo --done` |

A first word that isn't an op but looks like an item ("/todo call Daniel about SRT-296") → ask
whether to add it; don't guess.

**list** (read-only) — `--done` also lists items done in the last 7 days; `--all` every done item.
Print the Open items in file order, grouped `p1` / `p2` / `p3`, one line each:
`#id text — due <date> (overdue / in N days) — links — ↻ <session title>` (↻ only when the item has a `session` field). Mark **overdue** and items due within 2 days.
If an item links a PR that has since merged or closed (`gh pr view N -R contoroinc/<repo> --json state`),
say "PR merged — mark done? (`/todo done #id`)". No file yet → say the list is empty and show
`/todo add` usage. Don't change the file.
