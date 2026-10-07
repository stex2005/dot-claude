---
description: Show your open todo list (~/.claude/todo.md) by priority, with overdue and due-soon items flagged.
allowed-tools: Read, Bash(gh *), Bash(date *)
argument-hint: "[--all] [--done]"
---

Follow `~/.claude/docs/todo-format.md`. Read-only.

Arguments: $ARGUMENTS — `--done` also lists items done in the last 7 days; `--all` lists every done item.

Print the Open items in file order, grouped `p1` / `p2` / `p3`, one line each:
`#id text — due <date> (overdue / in N days) — links`. Mark **overdue** and items due within 2 days.
If an item links a PR that has since merged or closed (`gh pr view N -R contoroinc/<repo> --json state`),
say "PR merged — mark done? (`/todo-done #id`)". Don't change the file.
