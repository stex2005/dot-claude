---
name: release-scope
description: Use when adding, updating, removing or listing the features of an upcoming unloader release (v3.4, v4.0, ...) on the Jira SRT board, linking GitHub PRs to those Jira tickets, or refreshing the "vX.Y.Z Release Scope" Confluence page that lists each release's key features, owners and dates.
---

# Release scope (Jira SRT + Confluence)

## Overview

Jira is the source of truth. One **epic per release** on project `SRT` (board 505); the release's features are the epic's child tasks. The Confluence "Release Scope" page is a view generated from the epic. Every write — Jira or Confluence — is previewed and needs the user's explicit OK first, in one batch.

## Where things live

| Thing | Value |
|---|---|
| Atlassian cloudId | `contoro.atlassian.net` |
| Release epic | `project = SRT AND issuetype = Epic AND summary ~ "vX.Y"` (v3.4.0 → epic "v3.4"). Known: **SRT-265 = v3.4**, **SRT-284 = v4.0** |
| Features | `parent = <epic> ORDER BY key` |
| Confluence page | title `vX.Y.Z Release Scope`, space `Software1`. Known: v3.4.0 = page **1549697028**. Missing → ask where to create it; don't guess a parent |
| GitHub org | `contoroinc` (`gh search prs --owner contoroinc ...`) |

## Operations

Argument form: `/release-scope <op> [version|key] [...] [--jira | --confluence]`. No op → `list`.

**Target flag** — default is **both**: the Jira change, then the release's Confluence page regenerated from the updated epic, in one preview and one OK.
- `--jira` — Jira only; the page is left as is.
- `--confluence` — page only; no Jira writes. With `add`/`update`/`remove`, say the change must land in Jira first (the page is generated from it) and offer to run without the flag.

| Op | Jira part | Confluence part |
|---|---|---|
| **list [version]** | read-only: key, summary, assignee, status, due date | read-only: whether the page matches the epic |
| **add <version> "<summary>"** | `createJiraIssue` (project SRT, Task, `parent` = epic key); ask owner and due date (`lookupJiraAccountId`; `additional_fields: {"duedate": "YYYY-MM-DD"}`) | regenerate page |
| **update <key>** | summary / assignee / `duedate` / description via `editJiraIssue` | regenerate page |
| **remove <key>** | unparent `{"parent": null}`, or move to another release `{"parent": {"key": "<other epic>"}}`; never delete | regenerate page |
| **sync [version]** | link PRs into every ticket's description (below) | regenerate page |

## Linking PRs

PRs never contain SRT keys, so match on content: ticket summary/description vs PR title, body, branch name, changed files. A feature usually spans several repos — collect all of them. Hand the search to a subagent; it is a 15-repo fan-out.

There is no remote-link tool, so PRs go into the description as a managed section:

```markdown
## Pull requests
- contoroinc/unloading_robot_task_executor#857 — plan the dropoff swing against the cached octomap (draft)
- contoroinc/unloading_robot_debugger#135 — toggle whether RRT planning includes the octomap (draft)
```

- Read the description first (`getJiraIssue`, `responseContentFormat: "markdown"`). Keep all existing text; replace only an existing `## Pull requests` section, else append it.
- An empty description gets a 1–2 sentence summary of what the PRs do above the section.
- Write back with `editJiraIssue`, `contentFormat: "markdown"`.
- Only **high-confidence** matches are written. Medium/low ones are listed in the preview for the user to accept or reassign.

## Regenerating the Confluence page

A table with four columns — Jira, Feature, Owner, By. No status column:

```
<p>Key features for v3.4.0 (epic <a href=".../browse/SRT-265">SRT-265</a>, <a href="https://contoro.atlassian.net/jira/software/projects/SRT/boards/505">SRT board</a>). Expected cut: <time datetime="2026-10-22">Oct 22, 2026</time>. Updated <time datetime="2026-10-07">Oct 7, 2026</time>.</p>
<table><thead><tr><th>Jira</th><th>Feature</th><th>Owner</th><th>By</th></tr></thead><tbody>
<tr><td><a href=".../browse/SRT-292">SRT-292</a></td><td>Feature: Force Rescan from Cloud UI</td><td><span data-type="mention" data-user-id="AAID">@Name</span></td><td><time datetime="2026-10-09">Oct 9, 2026</time></td></tr>
<tr><td>↳ <a href=".../browse/SRT-297">SRT-297</a></td><td>Cloud UI: Force Rescan button next to pause/start</td><td><span data-type="mention" data-user-id="AAID">@Name</span></td><td><time datetime="2026-10-09">Oct 9, 2026</time></td></tr>
<tr><td><a href=".../browse/SRT-282">SRT-282</a></td><td>Octomap: Add Octomap during dropoff planning<br>Depends on: <span data-type="mention" data-user-id="AAID">@Name</span> — what they deliver</td><td>…</td><td><time datetime="2026-10-22">Oct 22, 2026</time> (cut)</td></tr>
</tbody></table>
```

- Rows: the epic's features ordered by key, each followed by its subtasks (`parent in (<feature keys>)`), marked `↳`.
- Feature = the Jira summary verbatim, minus a trailing period. To reword a title, `update` it in Jira — never only on the page.
- Owner = a mention built from the assignee's `accountId` (the user included). No assignee → `Unassigned`. Never invent an AAID.
- By = the ticket's `duedate`; none → the **expected cut date** = the epic's `duedate`, suffixed `(cut)`. The epic has no due date → ask for the cut date.
- The page is fully generated **except** the "Depends on" lines in the Feature cell: read the page first and carry them over per key. New dependencies only come from the user; never infer them.
- Anything else on the current page that the regeneration would change or drop is listed in the preview.
- Write with `updateConfluencePage` (`contentFormat: "html"`, `versionMessage: "release-scope sync from <epic>"`). Call `getContentFormatGuide` (`toolName: "updateConfluencePage"`) once first.

## The preview (required before any write)

One block listing every pending write:
1. Jira: per ticket — field → new value, plus the full new description when it changes.
2. Tickets owned by someone other than the user are marked **(owner: Name)**.
3. Confluence: one line per feature (`key — owner — by`), what gets dropped or changed, "will notify: …" (other people only), and how many rows fall back to the cut date (offer an `update` pass to set due dates first).
4. One question: apply all / apply some (which) / cancel.

Only an answer to this preview is the OK. "Just push it", "go ahead", or approval given before the preview existed does not skip it.

## Common mistakes

| Mistake | Fix |
|---|---|
| Writing to Jira/Confluence without the preview | Preview, then wait for the OK |
| Overwriting a hand-written description | Replace only `## Pull requests` |
| Mentioning someone from a guessed name | Use the assignee's `accountId` or `lookupJiraAccountId` |
| Treating "remove" as delete or cancel | Unparent (or re-parent) only |
| Assuming the assignee wrote the PRs | Flag it when PR authors differ from the assignee |
