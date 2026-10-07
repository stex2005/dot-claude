---
description: Pick what to do next from your todo list — top open item adjusted for deadlines and blockers, with a concrete first step.
allowed-tools: Read, Bash(gh *), Bash(git *), Bash(date *)
argument-hint: "[n]"
---

Follow `~/.claude/docs/todo-format.md`. Read-only. This ranks **the todo list only** — for PRs,
reviews and Jira run `/release-next`; for the PR you are on, `/pr-next`.

Arguments: $ARGUMENTS — optional `n`, how many to show (default 3).

1. Start from the Open order (it is the user's ranking).
2. Promote only for evidence, and say why: an item due today/overdue, or one whose linked PR is
   blocked on a cheap step (approved and waiting to merge, a merge conflict, a review thread). Never demote.
3. Skip items whose linked PRs are all merged → list them as "probably done" (`/todo-done --check`).
4. Show the top `n`: `#id text — why now — first concrete step`, with links.
5. Ask which to start (or none). On a pick, name the command that starts it (`/pr-create`,
   `/address-pr-comments N`, `/rebase`, `/start-plan`, `/release-scope update …`) and run it only if the user confirms.
