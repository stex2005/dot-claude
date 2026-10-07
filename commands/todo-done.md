---
description: Mark todo items done (by id or text match); also offers to close items whose linked PR merged.
allowed-tools: Read, Write, Edit, Bash(gh *)
argument-hint: "<#id | text> [...] | --check"
---

Follow `~/.claude/docs/todo-format.md`.

Arguments: $ARGUMENTS

- `#id` or a text fragment → move the item to the top of `## Done` with `- [x]` and `· done <today>`.
  A fragment that matches several items → list them and ask.
- `--check` → for every Open item with PR links, look up their state; list items whose PRs are all
  merged/closed and ask which to mark done. Jira links are informational only — never mark done from them alone.
- Show the moved lines. Never edit Jira or GitHub.
