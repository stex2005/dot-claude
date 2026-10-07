---
name: release-scope
description: Use when adding, updating, removing or listing the features of an upcoming unloader release (v3.4, v4.0, ...) on the Jira SRT board, linking GitHub PRs to those Jira tickets, or turning the team's "vX.Y.Z Release Scope" Confluence notes into Jira changes.
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
| Scope notebook | Confluence `vX.Y.Z Release Scope`, space `Software1`, under "Robot Release Scope" — find it by title (`searchConfluenceUsingCql`: `space = Software1 AND title = "vX.Y.Z Release Scope"`); never trust a cached page id (v3.4.0's was deleted; v4.0.0 = 1550319644 as of 2026-10-07). The team's hand-written notes during scope definition. **Read-only** — `getConfluencePage` (`contentFormat: "markdown"`); never update, create or delete it |
| GitHub org | `contoroinc` (`gh search prs --owner contoroinc ...`) |

## Operations

Argument form: `/release-scope <op> [version|key] [...]`. No op → `list`.

| Op | What it does |
|---|---|
| **list [version]** | read-only: features and their subtasks (`↳`) — key, summary, assignee, status, **priority**, due date — sorted by priority then key, plus the expected cut date |
| **add <version> "<summary>"** | `createJiraIssue` (project SRT, Task, `parent` = epic key); ask owner and due date (`lookupJiraAccountId`; `additional_fields: {"duedate": "YYYY-MM-DD"}`) |
| **update <key>** | summary / assignee / `duedate` / **`priority`** / description via `editJiraIssue` (`{"priority": {"name": "High"}}`) |
| **prioritize [version] "<A, B, C, …>"** | turn a ranked list into Jira priorities for the release (below) |
| **remove <key>** | unparent `{"parent": null}`, or move to another release `{"parent": {"key": "<other epic>"}}`; never delete |
| **sync [version]** | link PRs into every ticket's description (below) |

## Priorities

Jira's `priority` field is the record of what goes first. Use only the names the SRT project offers
(read them once with `getJiraIssueTypeMetaWithFields` for project SRT, issue type Task; `Medium`
is the default every ticket starts with).

`prioritize` takes the user's ranked list — ticket keys, or names that you resolve to keys
(e.g. "override grasps" → SRT-267); an item with no ticket is offered as an `add` first:

1. Map rank to priority in tiers: the top item(s) → `Highest`, the next ones → `High`, the rest of the
   list → `Medium`; features in the release that the list leaves out → `Low`. Show the mapping and
   let the user move items between tiers before anything is written.
2. Subtasks inherit their parent's priority unless they already have a higher one.
3. Flag conflicts, don't fix them: a lower-priority ticket due before a higher one, or a
   higher-priority ticket blocked by a lower one (e.g. its subtask, or a ticket named as its dependency).
4. The ordered list itself is also kept in the user's memory notes so `/pr-next` uses the exact order,
   which is finer-grained than five priority levels.

## Reading the scope notebook

`list` and `sync` also read the release's notebook page (missing page → skip, say so) and report, read-only:
- items discussed on the page with no matching Jira feature → offer `add` for each;
- Jira features the page says are cut, deferred or moved → offer `remove` (or re-parent);
- owners, dependencies or dates the page states that differ from Jira → offer `update`.

The page is the team's input; Jira is the record. Turn notes into Jira changes only through the normal preview.

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
| Editing the scope notebook | It is read-only; propose Jira changes instead |
| Overwriting a hand-written description | Replace only `## Pull requests` |
| Treating "remove" as delete or cancel | Unparent (or re-parent) only |
| Assuming the assignee wrote the PRs | Flag it when PR authors differ from the assignee |
