---
description: Add an item to your private todo list (~/.claude/todo.md) — one line, optional priority, due date and links.
allowed-tools: Read, Write, Edit
argument-hint: "\"<text>\" [--p 1|2|3] [--due YYYY-MM-DD|Oct 9|tomorrow] [--link SRT-292,TE#857]"
---

Follow `~/.claude/docs/todo-format.md` for the file and line format.

Arguments: $ARGUMENTS

1. Parse the text, `--p` (default `p2`), `--due` (resolve relative dates against today; ask if ambiguous), `--link`.
   With no `--link`, pick up obvious refs from the text itself (`SRT-292`, `TE#857`).
2. Insert under `## Open` at the **end of its priority bucket**, with the next id and `· added <today>`.
3. Show the new line and its position (`#9 — 3rd of 4 p1 items`). Never touch other lines.
