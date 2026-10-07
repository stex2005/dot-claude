# Todo file format (shared by the /todo-* commands)

The list lives in **`~/.claude/todo.md`** — private, never committed anywhere. Create it with the
skeleton below when missing. The user also edits it by hand, so read it fresh every time and
preserve anything you don't understand.

```markdown
# Todo

## Open
- [ ] #7 p1 Grasp debug: push and get review · due 2026-10-09 · link debugger#177, TE#966 · added 2026-10-07
- [ ] #8 p2 Add the vertical-gap ticket to v3.4 · link SRT-265 · added 2026-10-07

## Done
- [x] #3 p1 Retire MoveKuka step5 · link SRT-280 · done 2026-10-08
```

- One item per line: `- [ ] #<id> p<1-3> <text>` then optional ` · due YYYY-MM-DD`, ` · link <refs>`, ` · added YYYY-MM-DD`; done items add ` · done YYYY-MM-DD`.
- **The order of lines under `## Open` is the ranking.** `p1`–`p3` are coarse buckets; within a bucket, higher line = sooner. Keep Open sorted p1 → p3 without reordering inside a bucket unless asked.
- IDs are never reused: next id = highest id in the file + 1.
- Links: `SRT-123` (Jira), `repo#N` with the short repo names `debugger`, `TE` (task_executor), `PO` (process_orchestrator), `common`, `msgs`, `hal`, `perception`, `kuka_experimental`, `cloud-platform` — all under `contoroinc`.
- Done items stay under `## Done` (newest first). Items done more than 30 days ago may be pruned by `/todo-day`.
- Write with a single Edit/Write of the file; show the changed lines afterwards.
