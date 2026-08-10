---
description: Clean up after merged branches — worktrees, local/remote branches, stashes, plans and specs. Verifies no follow-up is owed, and confirms before deleting anything.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(rm *), Bash(pwd), Bash(for *), Read, Glob, Grep
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Current branch: !`git branch --show-current 2>/dev/null || echo "(not a git repo)"`
- Arguments: $ARGUMENTS

## Invocation forms

| Form | Meaning |
|---|---|
| `/cleanup-merged` | Sweep every candidate branch in scope |
| `/cleanup-merged <branch>` | Restrict to that one branch |
| `/cleanup-merged --repo <name>` | Restrict to one sub-repo (multi-repo mode only) |
| `/cleanup-merged --dry-run` | Report only — never prompt, never mutate |

Flags compose with a branch argument. `--dry-run` overrides everything else. `--repo` in
single-repo mode is an error — say so and stop.

## Your task

A merged branch leaves more behind than the branch: a worktree on disk, a remote branch, one
or more stashes, and a plan/spec pair under `docs/superpowers/`. Find all of it, **verify the
work is genuinely finished**, then remove it with the user's approval.

Verification is the gate, not a garnish. Nothing is removed for a branch that fails it.

## Workspace detection

1. **Single-repo mode**: current directory contains a `.git` folder → operate on this repo.
2. **Multi-repo mode**: current directory has no `.git`, but has subdirectories that do →
   sweep all of them.
3. **Error**: neither → tell the user and stop.

## Step 1: Refresh and orient

For each repo in scope:

```bash
git fetch --prune origin
```

`--prune` is required — it is what reveals branches whose upstream GitHub already deleted.

Determine the default branch: prefer
`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`; fall back to whichever of
`develop` / `main` / `master` exists locally.

## Step 2: Classify each branch as merged

Candidates are all local branches **minus the protected set**:

- the repo default branch
- `main`, `master`, `develop`
- `release-candidate/*`

Combine two signals per candidate:

```bash
# Primary — authoritative, and correctly recognises squash/rebase merges
gh pr list --head <branch> --state all --json number,state,mergedAt,url

# Secondary — covers branches merged without a PR
git branch --merged <default>
```

| Signals | Verdict |
|---|---|
| PR state is `MERGED`, **or** branch is an ancestor of default | **MERGED** → verify it |
| A PR exists and is `OPEN` | **NOT-MERGED** → skip silently |
| No PR **and** not an ancestor | **UNCLEAR** → report, never propose |

**If `gh` is unavailable or unauthenticated**, degrade to ancestry-only and say so loudly at
the top of the report. Ancestry alone under-detects squash merges — the common case in this
workflow — so the results are materially weaker.

A branch checked out in a worktree cannot be deleted while checked out. If it is the current
repo's HEAD, offer to switch to the default branch first. If another worktree holds it,
removing that worktree resolves it.

## Step 3: Verify no follow-up is needed

Run all four checks on every MERGED branch. Two block, two advise.

### 3.1 Commits pushed after the merge — HARD BLOCK

Do **not** use `git log <default>..<branch>` for this. After a squash merge the whole branch
looks unmerged, so that check would block everything.

Compare the local tip against the commit GitHub actually merged:

```bash
gh pr view <N> --json headRefOid,mergedAt,mergeCommit
```

If the local tip differs from `headRefOid`, commits landed after the merge and are genuinely
unaccounted for. List them with `git log <headRefOid>..<branch> --oneline` and **block**.

For an ancestry-merged branch with no PR this set is empty by definition — passes trivially.

### 3.2 Dirty worktree or unpushed work — HARD BLOCK

In the branch's worktree (located via `git worktree list --porcelain`):

```bash
git status --porcelain                             # uncommitted or untracked
git rev-list --count origin/<branch>..<branch>     # local commits not on origin
```

Either non-empty → **block**.

### 3.3 Unresolved review threads — NEEDS FOLLOW-UP

Query the PR's review threads for `isResolved: false`:

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!, $pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes { isResolved path line comments(first:1) { nodes { author { login } body url } } }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F pr=<N>
```

Unresolved threads on a merged PR mean feedback was never closed out. Report each with its
file, line, and link, and mark the branch NEEDS-FOLLOW-UP.

### 3.4 Open linked issues and new TODOs — ADVISORY

- Parse the PR body for `Closes #N` / `Fixes #N` / bare `#N`, then `gh issue view <N> --json state`.
- Grep the branch's diff for `TODO` / `FIXME` / `XXX` / `HACK` that the branch **added**.

Surface as warnings. These do **not** block — a merged feature can legitimately leave a
tracked follow-up issue open.

### Verdicts

| Verdict | Meaning |
|---|---|
| **CLEAN** | Merged, both hard blocks pass, no unresolved threads → artifacts proposed |
| **NEEDS-FOLLOW-UP** | Merged but failed a block or has unresolved threads → nothing deleted |
| **UNCLEAR** | Merge status not established → nothing deleted |

## Step 4: Discover artifacts

For CLEAN branches only.

| Artifact | How to find it | Note |
|---|---|---|
| Worktree | `git worktree list --porcelain`, matched by branch | — |
| Local branch | the branch itself | — |
| Remote branch | `git ls-remote --heads origin <branch>` | absent → "already deleted" |
| Plans / specs | see below | — |
| Stashes | `git stash list` | see below |

**Plan and spec attribution.** Search `docs/superpowers/plans/*.md` and
`docs/superpowers/specs/*.md`. A file is a candidate if **any** of: its content names the
branch; its filename slug overlaps the branch slug; it mentions the merged PR number.

A candidate is only proposed for deletion if it is additionally **done** — every checkbox is
`[x]`, or the file explicitly says DONE (the same bar `/prune-plans` applies). Matched but
not clearly done → report as UNCLEAR and keep.

**Stash attribution.** Attribute a stash to the branch only when its subject is
`WIP on <branch>:` / `On <branch>:` **and** its base commit is reachable from the branch.
One signal alone is not enough — mark it UNCLEAR and never propose it. Stashes are
unrecoverable once dropped, so the bar is deliberately higher here.

## Step 5: Report

One section per repo, grouped by verdict:

```
## task_executor  (on: develop)

### CLEAN — safe to remove (2)
| Branch | PR | Worktree | Remote | Plans/Specs | Stashes |
|---|---|---|---|---|---|
| feat/gripper-zones | #412 merged 3d ago | ../wt-gripper | present | plans/2026-07-02-gripper-zones.md | — |

### NEEDS FOLLOW-UP (1)
| Branch | PR | Why |
|---|---|---|
| feat/rc-check | #418 merged | 2 commits pushed after merge; 3 unresolved review threads |

### UNCLEAR — left alone (1)
| Branch | Why |
|---|---|
| spike/octomap | no PR, not an ancestor of develop |
```

Every flagged row must carry enough context — branch, PR number, `file:line`, sha — that the
user can act without re-running the query themselves.

**In `--dry-run` mode, stop here.**

## Step 6: Approval

After the full report, one grouped prompt:

> "I recommend removing the artifacts for the N branches marked CLEAN. Want me to:
> 1. Delete everything listed CLEAN
> 2. Only certain artifact types (branches / worktrees / plans+specs)
> 3. Let me pick individually
> 4. Skip — delete nothing"

**Wait for the response before touching anything.**

**Stashes are excluded from that prompt.** They get a second, separate confirmation — show
`git stash show --stat <ref>` for each candidate first, then ask. Dropping a stash cannot be
undone.

## Step 7: Execute

Run approved deletions in dependency order, so nothing is left half-removed:

1. `git worktree remove <path>` — must precede branch deletion; a checked-out branch cannot
   be deleted.
2. `git branch -d <branch>` — the safe form.
3. `git push origin --delete <branch>` — skip when the remote branch is already gone.
4. `rm <path>` for approved plan/spec files.
5. `git stash drop <ref>` — last, and only for separately-confirmed stashes.

If a step fails, report it and skip the remaining steps **for that branch only**; other
branches continue.

## Step 8: Summary

Close with three lists:

- what was deleted, per repo
- what was kept, and why
- **follow-ups still owed** — carried over from the NEEDS-FOLLOW-UP rows, so the user leaves
  the command knowing what is outstanding

## Rules

- Read-only until the user approves. Discovery, classification, and verification never mutate.
- NEVER delete anything classified UNCLEAR, or any branch in the protected set.
- NEVER delete a branch that failed a hard block, regardless of what was approved.
- `git branch -d`, never `-D` — if `-d` refuses, report why and ask for `-D` explicitly,
  naming the branch. Do not force by default.
- Stashes always require their own confirmation, separate from the main approval prompt.
- Never delete remote branches on any remote other than `origin`.
- Read the FULL content of a plan or spec before proposing it for deletion — don't classify
  on filename alone.
- `--dry-run` never prompts and never mutates.

## Out of scope

- Branches that were never merged — that stays a deliberate human decision.
- The stacked-PR step chain — the `/stack-*` commands own that lifecycle.
