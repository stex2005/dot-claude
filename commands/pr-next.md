---
description: Decide what to work on next — rank your open PRs, review requests, release-scope tickets, local unpushed work and parked notes, recommend a top 3, then hand off to the command that starts the picked item.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Bash(pwd *), Bash(cat *), Bash(find *), Bash(grep *), Bash(test *), Read, Glob, Grep
argument-hint: "[version] [--all]"
---

## Context

- Current directory: !`pwd`
- gh user: !`gh api user -q .login 2>/dev/null || echo "<gh unavailable>"`
- Current branch: !`git branch --show-current 2>/dev/null || echo "<not a git repo>"`
- Arguments: $ARGUMENTS — optional `[version]` (release whose scope counts as "in release"; default: the open SRT release epic with the nearest due date), `--all` (show every ranked item, not just top 3 + can-wait)

## What this does

Gathers everything that competes for your time, ranks it, and recommends what to do next. It is
**read-only until you pick an item**; then it hands off to the command that does the work. It
never writes to GitHub or Jira itself.

## Step 0 — Start from the current session's PR

Before looking anywhere else, look at what this session is working on.

1. **Find it:** the current repo's branch, plus every sibling repo (`../*/.git`) on the same
   branch name. For each one, `gh pr list --head <branch> --state all --json number,state,isDraft,url`.
   On a protected branch (`develop`, `main`, `release-candidate/*`) or with no PR and no commits
   ahead of the default branch, there's no current work. Say so and go to Step 1.
2. **Check what's left**, per repo:
   - local: uncommitted changes and unpushed commits (`git status --porcelain`, `git log @{u}..`)
   - PR: draft or ready, CI, `reviewDecision`, reviewers requested (none means nobody will look at it), `mergeable`, unresolved threads
   - the PR body still matches the commits (title/summary describe what the branch now does)
   - the Jira ticket it belongs to: listed in the ticket's `## Pull requests`, and the ticket's status matches (e.g. still `To Do` while the PR is up)
   - sibling PRs on the same branch reference each other
3. **Report it first**, as "Current: <branch>" with the remaining steps in order, each with its
   hand-off (`/commit`, `/pr-create`, `/address-pr-comments`, `/rebase`, `/release-scope update`).
   If nothing is left except waiting for review or merge, say "waiting on <who>" and move on.

The current PR outranks everything in Step 2 **unless** it's only waiting on other people. Then
it goes at the top of "can wait" with who it's waiting on, and the ranking picks what's next.

## Step 1 — Gather (read-only, in parallel)

| Source | What | How |
|---|---|---|
| Your PRs | open + draft PRs you authored in `contoroinc` | `gh search prs --owner contoroinc --author @me --state open --json repository,number,title,isDraft,updatedAt,url`; per PR `gh pr view N -R contoroinc/<repo> --json reviewDecision,mergeable,statusCheckRollup,reviewRequests,baseRefName` and unresolved review threads (graphql `reviewThreads { isResolved }`) |
| Review requests | PRs waiting on your review | `gh search prs --owner contoroinc --review-requested @me --state open` |
| Release scope | your tickets in the release epic and the next one | `/release-scope` conventions: project `SRT`, epic `summary ~ "vX.Y"`, `parent = <epic>`; the epic's `duedate` is the cut date. Also subtasks under **your** tickets that others own, and each ticket's `## Pull requests` section |
| Local work | uncommitted / unpushed work in the workspace repos | for each `../*/.git` and `.`: `git status --porcelain`, `git rev-list --count @{u}..` (skip repos with no upstream) |
| Notes | parked items and TODOs | the project memory notes describing parked or pending work, the workspace `TODO.md`, the release's scope notebook (read-only) |

A source that fails (no `gh`, no Atlassian) is skipped and **named** at the top of the output.

## Step 2 — Rank

**A priority order the user stated wins.** If the user's memory notes or this conversation hold
an explicit order ("by priority: A, B, C"), rank those items in that order above the tiers
below. Still flag deadline conflicts (an item due before something ranked above it), but don't
reorder for them.

Otherwise: highest tier first; within a tier, earliest deadline, then smallest remaining step.

| Tier | Qualifies when |
|---|---|
| 1 · **Blocking someone** | your review is requested; a teammate's subtask under your ticket is waiting on you; another ticket or PR lists yours as its dependency; a merged-upstream rebase someone asked for |
| 2 · **Almost done** | your PR is approved or green and only needs: merge, rebase/conflict fix, or replies to unresolved threads |
| 3 · **Deadline** | overdue, or due before the cut date |
| 4 · **Release risk** | a ticket in the release still `To Do` / `Development` with no PR, or PRs still draft, as the cut approaches |
| 5 · **Everything else** | open PRs outside any release ticket, local unpushed work, parked notes, ideas |

An item that matches several tiers sits in the highest. Unpushed local work that exists nowhere
else is always called out, whatever its tier.

## Step 3 — Report

```
Current: feat/stefano/grasp-debug — debugger#177, TE#966
- push 4 unpushed commits (debugger 1 + uncommitted scene-api.js, TE 3)   → /commit
- no reviewers requested on either PR                                      → request review
- SRT-293 doesn't list these PRs                                           → /release-scope sync

Next up (v3.4 cut Oct 22 — 15 days)
1. Review hal#270 for Edward — blocks his SRT-301 PR                       → /pr-review 270
2. TE#857 (SRT-282) — 2 unresolved threads, CI green                       → /address-pr-comments 857
3. SRT-292 Force Rescan — due Oct 9, no PR yet; Daniel's SRT-297 waits on it → /pr-create

Can wait
- debugger#161 TOPP-RA — draft, not in any release
- parked: rebase v3.1 branches once #71 merges (#71 still open)

Not in any release: 11 open PRs (debugger#173, #161, hal#245, …)
Skipped sources: none
```

Each item: tier, one line on **why now**, the **first concrete step**, link, and the hand-off
command. Every PR number, ticket key and date traces to Step 1 output — never invent one.

## Step 4 — Pick and hand off

Ask with `AskUserQuestion`: "finish current" (when Step 0 found steps left), the top 3 (or the
top 2 when "finish current" takes a slot), plus "none — just the report". On a pick, invoke the
matching command and stop being in charge:

| Item needs | Hand off to |
|---|---|
| a PR that doesn't exist yet (branch has commits) | `/pr-create` |
| work that hasn't started (no branch) | `/start-plan` |
| review of someone else's PR | `/pr-review <N>` |
| replies to review threads | `/address-pr-comments <N>` |
| rebase / conflict fix | `/rebase` |
| Jira change (owner, due date, scope) | `/release-scope update <key>` |

Before handing off to anything that switches branches, check the target repo's working tree; if
it's dirty or another branch is checked out for in-progress work, say so and ask first.

## Rules

- Read-only until the hand-off. This command never comments, merges, pushes, or edits Jira.
- Rank on evidence from Step 1, not on guesses about importance; when two items tie, prefer the
  one that unblocks another person.
- Name skipped sources; silence is not "nothing found".
- Don't re-rank what the user already decided — if they say an item is parked, keep it in "can wait".
