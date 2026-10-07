---
description: Daily planning — morning plan from your todo list and deadlines, or an evening wrap-up of what got done and what carries over.
allowed-tools: Read, Write, Edit, Bash(gh *), Bash(git *), Bash(date *), Bash(ls *), Bash(cd *)
argument-hint: "[start | end]"
---

Follow `~/.claude/docs/todo-format.md`.

Arguments: $ARGUMENTS — `start` or `end`; with neither, use `start` before 14:00 local time, else `end`.

**start (morning)**
1. Read Open. Today's plan = items due today or overdue, then the top items by order — at most 5 total.
2. Add what is waiting on the user from outside the list: PRs whose review is requested from them
   (`gh search prs --owner contoroinc --review-requested @me --state open`). Mark these "not on your list".
3. Print the plan; offer to add any of the outside items with `/todo-add`. Write nothing without a yes.

**end (wrap-up)**
1. Gather today's activity: the user's commits today in the workspace repos (`git log --since=midnight --author=<git user>`),
   PRs they opened/merged/reviewed today (`gh search prs --owner contoroinc --author @me --updated <today>`, and `--reviewed-by @me`).
2. Match activity to Open items (by links, then by text). Propose: mark done (merged / clearly finished),
   keep (in progress — say what moved), and new items discovered from activity that aren't on the list.
3. Show the proposal, **ask**, then apply. Prune Done items older than 30 days only if the user agrees.
