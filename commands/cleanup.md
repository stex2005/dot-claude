---
description: Clean up after finished branches — starts from the current repo and branch, pulls in matching branches in sibling repos, then offers an interactive selection of worktrees, branches, remotes, stashes, plans and specs to delete.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(rm *), Bash(pwd), Bash(for *), Read, Glob, Grep, AskUserQuestion
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Current branch: !`git branch --show-current 2>/dev/null || echo "(not a git repo)"`
- Sibling directories: !`ls -d ../*/ 2>/dev/null || echo "(none)"`
- Arguments: $ARGUMENTS

## Invocation forms

| Form | Meaning |
|---|---|
| `/cleanup` | Anchor on the current branch; add its matches in sibling repos |
| `/cleanup <branch>` | Anchor on that branch instead of the current one |
| `/cleanup --all` | Sweep every candidate branch in the current repo and its siblings |
| `/cleanup --repo <name>` | Restrict the scan to the named repo(s); repeatable |
| `/cleanup --dry-run` | Report only — never prompt, never mutate |

Flags compose with a branch argument. `--dry-run` overrides everything else.

## Your task

A finished branch leaves more behind than the branch: a worktree on disk, a remote branch, one
or more stashes, and a plan/spec pair under `docs/superpowers/`. In a multi-repo codebase it
leaves that trail in *every* repo the work touched. Find all of it, **verify the work is
genuinely finished**, then remove what the user selects.

Verification is the gate, not a garnish. Nothing is removed for a branch that fails a hard block,
regardless of what the user selected.

## Step 1: Anchor on the current repo and branch

1. Determine the current repo: the cwd if it contains `.git`, otherwise the nearest ancestor that
   does (`git rev-parse --show-toplevel`). If there is none → tell the user and stop.
2. Determine the anchor branch:
   - An explicit `<branch>` argument wins. Resolve it against the local branch list:
     - **Exact name** → use it.
     - **No exact match** → look for near-matches: a unique substring match, a unique match
       ignoring the type prefix, or a single branch within a small edit distance (typos like
       `relese-cmd-expansion` for `fix/release-cmd-expansion`). Name the branch you resolved to
       and **confirm before acting on it**.
     - **Several near-matches, or none** → list what you found and stop. Never guess silently.
   - Otherwise `git branch --show-current`.
3. **If the anchor is a protected branch** — the repo default, `main`, `master`, `develop`, or
   `release-candidate/*` — there is no anchor. Say so explicitly and fall back to `--all`
   behaviour for this repo and its siblings. Do not silently do nothing.
4. Detached HEAD with no branch argument → same fallback, same explicit notice.

Under `--all` the anchor still matters: it orders the report, it just no longer restricts it.

## Step 2: Discover sibling repos

Scan the peer directories of the current repo — `../*/` — for those containing `.git`. Skip the
current repo itself. `--repo <name>` restricts this set to the named repos.

For each peer, look for a branch belonging to the anchor's work item:

| Match | Rule | Marked as |
|---|---|---|
| **Exact** | a local branch with the same full name | — |
| **Fuzzy** | same slug under a different type prefix (`feat/x` vs `fix/x`) | `~fuzzy` |
| **None** | no branch matches | scanned, no match |

Group every match — the anchor plus its siblings — into one **work item**. The work item is the
unit the user selects.

**Always report the peers you scanned and found nothing in.** A silent scan leaves the user
unable to tell whether a repo was clean or was never looked at.

## Step 3: Refresh and classify

For each repo in scope:

```bash
git fetch --prune origin
```

`--prune` is required — it is what reveals branches whose upstream GitHub already deleted.

Determine the default branch: prefer
`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`; fall back to whichever of
`develop` / `main` / `master` exists locally.

Under `--all`, candidates are all local branches **minus the protected set** (the repo default,
`main`, `master`, `develop`, `release-candidate/*`). Protected branches are never candidates,
under any flag.

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
| A PR exists and is `OPEN` | **UNMERGED** → offered separately, see Step 5 |
| No PR **and** not an ancestor | **UNMERGED** → offered separately, see Step 5 |

**If `gh` is unavailable or unauthenticated**, degrade to ancestry-only and say so loudly at the
top of the report. Ancestry alone under-detects squash merges — the common case in this
workflow — so the results are materially weaker, and more branches will land in UNMERGED than
truly belong there.

**When the anchor is the current HEAD, its verdict decides what happens** — being checked out is
not itself a reason to refuse. Merging your PR and then cleaning up the branch you are standing
on is the single most common way this command is used.

| Anchor is current HEAD and… | Behaviour |
|---|---|
| **CLEAN** | Offer it, with the checkout as part of the action: switch to the default branch, fast-forward it, then delete. Say so in the option — the user is agreeing to move off the branch too. |
| **UNMERGED** | Never offer it. This is work in progress; you are standing on it precisely because it is not finished. |
| **Failed a hard block** | Never offer it, same as any other row. |

Any other branch checked out in a worktree cannot be deleted while checked out — removing that
worktree resolves it.

## Step 4: Verify no follow-up is needed

Run all four checks on every MERGED branch, in every repo of the work item. Two block, two advise.

**The two hard blocks (4.1, 4.2) also run on UNMERGED candidates.** An unmerged branch is the
one most likely to hold work that exists nowhere else, so it gets *more* scrutiny than a merged
one, not less. An unmerged branch that fails a hard block is never offered — not even behind the
⚠ prompt.

### 4.1 Commits pushed after the merge — HARD BLOCK

Do **not** use `git log <default>..<branch>` for this. After a squash merge the whole branch
looks unmerged, so that check would block everything.

Compare the local tip against the commit GitHub actually merged. When a branch has several
merged PRs (it was reused after a first merge), take the **most recent** one by `mergedAt`:

```bash
gh pr list --head <branch> --state merged --json number,headRefOid,mergedAt \
  --jq 'sort_by(.mergedAt) | last'
```

**Block on the commit list, never on tip inequality.** The test is:

```bash
git log <headRefOid>..<branch> --oneline    # commits the merge did not include
```

Non-empty → commits landed after the merge and are genuinely unaccounted for. List them and
**block**.

Empty → **pass**, even when the local tip differs from `headRefOid`. A tip that differs with an
empty list means the branch is merely *behind* the merged head — stale, not unaccounted. Testing
`tip != headRefOid` instead would block every stale branch, which is most of them.

For an ancestry-merged branch with no PR this set is empty by definition — passes trivially.

### 4.2 Dirty worktree or unpushed work — HARD BLOCK

In the branch's worktree (located via `git worktree list --porcelain`):

```bash
git status --porcelain                             # uncommitted or untracked
git rev-list --count origin/<branch>..<branch>     # local commits not on origin
```

Either non-empty → **block**.

### 4.3 Unresolved review threads — NEEDS FOLLOW-UP

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

Unresolved threads on a merged PR mean feedback was never closed out. Report each with its file,
line, and link, and mark that repo's row NEEDS-FOLLOW-UP.

### 4.4 Open linked issues and new TODOs — ADVISORY

- Parse the PR body for `Closes #N` / `Fixes #N` / bare `#N`, then `gh issue view <N> --json state`.
- Grep the branch's diff for `TODO` / `FIXME` / `XXX` / `HACK` that the branch **added**.

Surface as warnings. These do **not** block — a merged feature can legitimately leave a tracked
follow-up issue open.

### Verdicts

Verdicts are **per repo**, not per work item.

| Verdict | Meaning |
|---|---|
| **CLEAN** | Merged, both hard blocks pass, no unresolved threads → selectable |
| **NEEDS-FOLLOW-UP** | Merged but failed a block or has unresolved threads → locked, never deleted |
| **UNMERGED** | Merge status not established, or PR still open → offered only via the separate ⚠ prompt, and only if both hard blocks pass |

A work item whose repos disagree is **partially selectable**: the CLEAN rows go, the
NEEDS-FOLLOW-UP rows are excluded and reported as excluded. Selecting the work item never
overrides a hard block on one of its rows.

## Step 5: Discover artifacts

For CLEAN rows, and for UNMERGED rows the user later confirms.

| Artifact | How to find it | Note |
|---|---|---|
| Worktree | `git worktree list --porcelain`, matched by branch | — |
| Local branch | the branch itself | — |
| Remote branch | `git ls-remote --heads origin <branch>` | absent → "already deleted" |
| Plans / specs | see below | — |
| Stashes | `git stash list` | see below |

**Plan and spec attribution.** Search `docs/superpowers/plans/*.md` and
`docs/superpowers/specs/*.md` in each repo of the work item. A file is a candidate if **any** of:
its content names the branch; its filename slug overlaps the branch slug; it mentions the merged
PR number.

A candidate is only proposed for deletion if it is additionally **done** — every checkbox is
`[x]`, or the file explicitly says DONE (the same bar `/prune-plans` applies). Matched but not
clearly done → report and keep.

**Stash attribution.** Attribute a stash to the branch only when its subject is
`WIP on <branch>:` / `On <branch>:` **and** its base commit is reachable from the branch. One
signal alone is not enough — report it and never propose it. Stashes are unrecoverable once
dropped, so the bar is deliberately higher here.

## Step 6: Report

Lead with the anchor, then the rest. One block per work item:

```
Anchor: feat/gripper-zones  (task_executor, on develop)
Scanned siblings: duckctl ✓  unloader_msgs ✓  perception — no match  vision — no match

### feat/gripper-zones — CLEAN in 2 of 3 repos
| Repo | PR | Verdict | Worktree | Remote | Plans/Specs | Stashes |
|---|---|---|---|---|---|---|
| task_executor | #412 merged 3d ago | CLEAN | ../wt-gripper | present | plans/2026-07-02-gripper-zones.md | — |
| duckctl | #97 merged 3d ago | CLEAN | — | present | — | — |
| unloader_msgs | #31 merged | NEEDS-FOLLOW-UP | — | present | — | — |
      └ 3 unresolved review threads: msgs/Grip.msg:14, :22, :30 → <urls>

### UNMERGED — offered separately (2)
| Repo | Branch | Why | State |
|---|---|---|---|
| duckctl | spike/octomap | no PR, not an ancestor of develop | 12 commits |
| task_executor | wip/teleop | PR #420 open | 3 commits, 1 unpushed |
```

Every flagged row must carry enough context — repo, branch, PR number, `file:line`, sha — that
the user can act without re-running the query themselves.

**In `--dry-run` mode, stop here.** Never prompt, never mutate.

## Step 7: Interactive selection

Use `AskUserQuestion` with `multiSelect: true`. One option per **work item** (not per repo) so a
cross-repo branch is picked once; the option description names the repos and artifact counts it
covers.

- 4 options per question, up to 4 questions per call → 16 candidates per round. More than that
  → a second round, most relevant first.
- **Ordering:** the anchor's work item, then the remaining merged work items (only present under
  `--all`), then unmerged last.
- **UNMERGED candidates never share a question with CLEAN ones.** They get their own question,
  each label prefixed `⚠`, each description stating what would be lost (commit count, unpushed
  count, open PR number). Only unmerged branches that passed both hard blocks appear here, and
  never the current HEAD — an unmerged branch you are standing on is work in progress.
- NEEDS-FOLLOW-UP rows are never offered. They appear in the report only.

Then a second question for **artifact types** across the whole selection — worktrees, local
branches, remote branches, plans+specs — defaulting to all of them. Stashes are deliberately
absent from this list.

**Skip this question when the selection holds only one artifact type** (typically just branches
and their remotes). Asking the user to choose from a list of one is noise; state what will run
instead and go straight to execution.

**Two extra confirmations, both after the selection questions:**

1. **Unmerged branches.** If any were selected, show them again with their commit counts and ask
   for an explicit yes. `git branch -d` will refuse them; deleting one means `-D`, which discards
   commits that exist nowhere else. Name the branches in the question.
2. **Stashes.** Show `git stash show --stat <ref>` for each candidate first, then ask. Dropping a
   stash cannot be undone.

**Wait for each response before touching anything.**

## Step 8: Execute

Run approved deletions per repo, in dependency order, so nothing is left half-removed:

0. If the selection includes the current HEAD, switch off it first — `git checkout <default>`,
   then `git merge --ff-only origin/<default>` so the user is left on an up-to-date default
   branch rather than a stale one.
1. `git worktree remove <path>` — must precede branch deletion; a checked-out branch cannot be
   deleted.
2. `git branch -d <branch>` — the safe form. `-D` only for separately-confirmed unmerged branches.
3. `git push origin --delete <branch>` — skip when the remote branch is already gone.
4. `rm <path>` for approved plan/spec files.
5. `git stash drop <ref>` — last, and only for separately-confirmed stashes.

If a step fails, report it and skip the remaining steps **for that repo only**; other repos in the
work item, and other work items, continue.

## Step 9: Summary

Close with three lists:

- what was deleted, per work item and repo
- what was kept, and why
- **follow-ups still owed** — carried over from the NEEDS-FOLLOW-UP rows, so the user leaves the
  command knowing what is outstanding

## Rules

- Read-only until the user selects. Discovery, classification, and verification never mutate.
- NEVER delete a branch in the protected set, or a row that failed a hard block — even when its
  work item was selected.
- NEVER delete an unmerged branch without its own explicit confirmation, named branch by branch.
- NEVER offer the current HEAD when it is UNMERGED or failed a hard block. A CLEAN current HEAD
  may be offered, provided the option states that you will switch to the default branch first.
- Hard blocks 4.1 and 4.2 apply to unmerged candidates too, not only merged ones.
- `git branch -d`, never `-D`, for merged branches. If `-d` refuses one, report why and ask
  before forcing.
- Stashes always require their own confirmation, separate from the main selection.
- Never delete remote branches on any remote other than `origin`.
- Read the FULL content of a plan or spec before proposing it — don't classify on filename alone.
- Report sibling repos that were scanned and matched nothing. Silence is not a result.
- `--dry-run` never prompts and never mutates.

## Out of scope

- The stacked-PR step chain — the `/stack-*` commands own that lifecycle.
