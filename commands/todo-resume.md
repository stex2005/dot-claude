---
description: Find the Claude Code session that works on a todo item and print the command to resume it; link item ↔ session.
allowed-tools: Read, Write, Edit, Bash(python3 *)
argument-hint: "<#id | text> | --link-all"
---

Follow `~/.claude/docs/todo-format.md` (see **Sessions**).

Arguments: $ARGUMENTS

- **`#id` or text** → find the item, then its sessions (format doc, "Matching"). Print, newest first:
  `title — last active — branch — launch dir`, and for the best match the ready-to-paste
  `cd <launch-dir> && claude --resume <session-id>`. If the item has no `session` field yet and
  there's a confident match, ask whether to link it; write only on yes.
  No match → say so and suggest starting one: `cd <repo> && claude`, then `/rename <item-slug>` so
  the next lookup finds it.
- **`--link-all`** → propose a session for every Open item without one (best match, or "none"),
  show the table, ask which to apply, then write them in one edit.
- You can't switch the user's terminal to another session — hand over the command.
