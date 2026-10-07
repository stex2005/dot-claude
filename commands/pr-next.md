---
description: What's next within the PR you're on — check the current branch's PR (and its sibling-repo PRs) for what's left before it can merge, in order, and hand off the next step.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Bash(pwd *), Bash(test *), Read, Glob, Grep
argument-hint: "[branch]"
---

## Context

- Current directory: !`pwd`
- Current branch: !`git branch --show-current 2>/dev/null || echo "<not a git repo>"`
- Arguments: $ARGUMENTS — optional branch name (default: the current branch)

## What this does

Answers "what's left on this PR?" for the work you're in the middle of. It looks only at the
current branch's PR — across every repo that has the same branch — and lists the remaining steps
to get it merged, in order. Read-only until you pick a step. For choosing *which* work to do next
across the release, use `/release-next`; for personal items, `/todo-next`.

## Step 1 — Find the PR(s)

1. Branch = the argument, else the current branch. On a protected branch (`develop`, `main`,
   `master`, `release-candidate/*`) or detached HEAD → say there's no PR in progress, suggest
   `/release-next`, and stop.
2. Repos = the current repo plus every sibling (`../*/.git`) that has a local or `origin/` branch with
   the same name.
3. Per repo: `gh pr list --head <branch> --state all --json number,state,isDraft,url,title,body,baseRefName`.
   No PR yet but commits ahead of the base → the first step is `/pr-create`.

## Step 2 — Check what's left (per repo)

Go through these in order; each failed check becomes a step.

| # | Check | How | Step it yields |
|---|---|---|---|
| 1 | Uncommitted changes | `git status --porcelain` | commit → `/commit` |
| 2 | Unpushed commits | `git log @{u}..` | push |
| 3 | Behind base / conflicts | `mergeable`, `git rev-list --count HEAD..origin/<base>` | `/rebase` |
| 4 | CI | `statusCheckRollup` — failing check names + link | fix the named check |
| 5 | Unresolved review threads / changes requested | graphql `reviewThreads { isResolved }`, `reviewDecision` | `/address-pr-comments <N>` |
| 6 | Draft | `isDraft` | mark ready (`gh pr ready`) — only when 1–5 are clear |
| 7 | No reviewers | `reviewRequests` empty and no reviews | request review |
| 8 | PR body stale | title/summary vs the commits since the body was written | update the body |
| 9 | Cross-repo links | sibling PRs on the same branch mention each other | add the cross-references |
| 10 | Release ticket | the SRT ticket's `## Pull requests` lists this PR, and its status fits (not still `To Do`) | `/release-scope sync` or `update <key>` |

Waiting only on other people (approved-pending-merge by someone else, review requested and pending)
is not a step — report it as "waiting on <who>".

## Step 3 — Report

```
feat/stefano/grasp-debug — debugger#177, TE#966 (SRT-293)
Next: commit scene-api.js and push 1+3 commits                → /commit, then push
Then:
  2. request reviewers on #177 and #966 (none yet)
  3. add #177/#966 to SRT-293's Pull requests                   → /release-scope sync
Waiting on: —
```

Lead with the single **next** step, then the rest in order, then what's waiting on others. Every
claim traces to command output; cite PR numbers, failing check names, `file:line` for threads.

## Step 4 — Hand off

Ask with `AskUserQuestion`: do the next step / pick another step / none. On a pick, run the matching
command (`/commit`, `/rebase`, `/address-pr-comments N`, `/pr-create`, `/release-scope …`). Pushing,
`gh pr ready` and requesting reviewers are outward actions — confirm the exact command first.

## Rules

- Only this PR. Don't rank other work — that's `/release-next`.
- Read-only until the user picks a step.
- Another session may be working on the same branch: if the working tree changes while you check,
  say so and re-check before acting.
