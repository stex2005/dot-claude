---
description: Re-rank your todo list from a priority order you give ("A, B, C…"), or interactively review it.
allowed-tools: Read, Write, Edit
argument-hint: "[\"<A, B, C, …>\"]"
---

Follow `~/.claude/docs/todo-format.md`.

Arguments: $ARGUMENTS

- **With a list:** resolve each name to an Open item (id, text or link match). Unmatched names →
  offer to add them (`/todo-add` semantics). Rewrite `## Open` in the given order; set `p1` on the
  first third, `p2` on the next, `p3` on the rest, unless the user gave buckets. Items not named
  keep their relative order after the named ones.
- **Without a list:** show Open with positions and ask for the new order or moves (`#9 above #4`, `#5 → p3`).
- Show before → after and **ask before writing**.
- If the reordered items carry `SRT-` links, mention that `/release-scope prioritize` can mirror the
  order onto Jira — don't run it.
