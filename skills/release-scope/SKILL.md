---
name: release-scope
description: Use when adding, updating, removing or listing the features of an upcoming unloader release (v3.4, v4.0, ...) on the Jira SRT board, or linking GitHub PRs to those Jira tickets.
---

# Release scope (Jira SRT)

## Overview

Jira is the single place a release's scope lives. One **epic per release** on project `SRT` (board 505); the release's features are the epic's child tasks, with their subtasks under them. Every Jira write is previewed and needs the user's explicit OK first, in one batch.

## Where things live

| Thing | Value |
|---|---|
| Atlassian cloudId | `contoro.atlassian.net` |
| Release epic | `project = SRT AND issuetype = Epic AND summary ~ "vX.Y"` (v3.4.0 → epic "v3.4"). Known: **SRT-265 = v3.4**, **SRT-284 = v4.0**. The epic's `duedate` is the expected cut date |
| Features | `parent = <epic> ORDER BY key`; subtasks: `parent in (<feature keys>)` |
| GitHub org | `contoroinc` (`gh search prs --owner contoroinc ...`) |

## Operations

Argument form: `/release-scope <op> [version|key] [...]`. No op → `list`.

| Op | What it does |
|---|---|
| **list [version]** | read-only: features and their subtasks (`↳`) — key, summary, assignee, status, due date — plus the expected cut date |
| **add <version> "<summary>"** | `createJiraIssue` (project SRT, Task, `parent` = epic key); ask owner and due date (`lookupJiraAccountId`; `additional_fields: {"duedate": "YYYY-MM-DD"}`) |
| **update <key>** | summary / assignee / `duedate` / description via `editJiraIssue` |
| **remove <key>** | unparent `{"parent": null}`, or move to another release `{"parent": {"key": "<other epic>"}}`; never delete |
| **sync [version]** | link PRs into every ticket's description (below) |

## Linking PRs

PRs never contain SRT keys, so match on content: ticket summary/description vs PR title, body, branch name, changed files. A feature usually spans several repos — collect all of them. Hand the search to a subagent; it is a 15-repo fan-out.

There is no remote-link tool, so PRs go into the description as a managed section:

```markdown
## Pull requests
- contoroinc/unloading_robot_task_executor#857 — plan the dropoff swing against the cached octomap (draft)
- contoroinc/unloading_robot_debugger#135 — toggle whether RRT planning includes the octomap (draft)
```

- Read the description first (`getJiraIssue`, `responseContentFormat: "markdown"`). Keep all existing text; replace only an existing `## Pull requests` section, else append it. A description that already lists its PRs by hand (another heading or a table) is left alone.
- An empty description gets a 1–2 sentence summary of what the PRs do above the section.
- Write back with `editJiraIssue`, `contentFormat: "markdown"`.
- Only **high-confidence** matches are written. Medium/low ones are listed in the preview for the user to accept or reassign.

## The preview (required before any write)

One block listing every pending write:
1. Per ticket — field → new value, plus the full new description when it changes.
2. Tickets owned by someone other than the user are marked **(owner: Name)**.
3. One question: apply all / apply some (which) / cancel.

Only an answer to this preview is the OK. "Just push it", "go ahead", or approval given before the preview existed does not skip it.

## Common mistakes

| Mistake | Fix |
|---|---|
| Writing to Jira without the preview | Preview, then wait for the OK |
| Overwriting a hand-written description | Replace only `## Pull requests` |
| Treating "remove" as delete or cancel | Unparent (or re-parent) only |
| Assuming the assignee wrote the PRs | Flag it when PR authors differ from the assignee |
