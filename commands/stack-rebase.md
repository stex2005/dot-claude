---
description: Sync every repo's stack via gh stack sync — fetch, cascade-rebase, push, sync PR state, and prune — after a base branch or a PR merges. Owns retargeting after merge.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *)
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: repo name in multi-repo mode — see Step 0)

## Preflight

Run the guard block from `docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack sync` is the only supported mechanism for retargeting, rebasing, and
pruning the stack — **never** fall back to a hand-rolled per-branch `git rebase` chain,
even if the guard fails. A silent fallback would push branches (or skip pushing them)
without `gh stack`'s own bookkeeping, leaving its state and the manifest out of sync.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is read,
and — for branches `--prune` deletes — written, only when `MODE=multi`. In single-repo
mode there is no manifest to prune; Step 5 below does not apply.

**This command owns retargeting after merge.** `/stack-create-pr` deliberately has no
`retarget` mode (per `docs/stacked-pr-workflow.md#workflow`): once a PR merges, its
sibling above it is left pointing at a stale base until `gh stack sync` retargets,
rebases, and prunes it — that happens here, in one call per repo, not as a separate
manual step.

## Your task

### Step 0: Resolve repo filter (multi-repo mode only)

Same convention as `/stack-create-pr`'s and `/stack-status`'s Step 0: if `$ARGUMENTS` is
non-empty, resolve it against `repos()` — exact match first, then substring match against
subdirectory names. If it resolves, restrict this run to that one repo. If nothing
matches, report the available repos (from `repos()`) and stop.

In single-repo mode there is no repo-name concept — a non-empty `$ARGUMENTS` is ignored.

An empty `$ARGUMENTS` means every repo from `repos()` (multi-repo mode) or just the
current repo (single-repo mode).

### Step 1: Sync each target repo

For each target repo, in order, run inside it:

```bash
cd "$WS/$repo"   # multi-repo mode; current directory in single-repo mode
gh stack view --json >/dev/null 2>&1; rc_check=$?
if [ "$rc_check" -eq 2 ]; then
  echo "$repo: no stack — skipping"
  continue
fi

pre=$(gh stack view --json 2>/dev/null)
before=$(jq -r '.branches[].name' <<<"$pre")
before_needs=$(jq -r '[.branches[].needsRebase] | any' <<<"$pre")
out=$(gh stack sync --prune 2>&1); rc=$?
after=$(gh stack view --json 2>/dev/null | jq -r '.branches[].name')
```

`rc_check == 2` means "no stack in this repo" — record it and move on, not an error, per
the guard's contract (same rule `/stack-status` and `/stack-checkout` use). Capture `$out`
(both stdout and stderr), `$rc`, `$before`, `$before_needs`, and `$after` for every repo
that has a stack — Steps 2 through 5 all need them, and `$rc` alone is not sufficient to
determine success (Step 3).

### Step 2: The conflict path (exit code 3)

Exit code 3 means a rebase conflict — this is now **locally confirmed directly through
`gh stack sync --prune`** (not just inferred from `gh stack rebase`), using a fixture with
a local bare repo as `origin` (`git init --bare` + `git remote add origin <path>` — zero
GitHub contact, since a bare repo on disk is not a GitHub remote). Observed output:

```
✓ Fetched latest main from origin
✓ Trunk main is already up to date

Rebasing stack ...
✗ Conflict detected rebasing layer1 onto main
  All branches restored to their original state.
  Run `gh stack rebase` to resolve conflicts interactively.
```

**Important, and confirmed by checking `git status` immediately afterward: `gh stack
sync`'s own conflict handling already restores the working tree and every branch to their
pre-sync state — it does not leave the repo mid-rebase.** This is a genuinely different
shape from `gh stack rebase` run directly (Task brief's original description, still
accurate for `gh stack rebase` itself): that command leaves conflict markers staged for
resolution, with `git add` then `gh stack rebase --continue` as the next step. `sync`
instead tells you to run `gh stack rebase` — with no flags — to *enter* that interactive
resolve flow, which will reproduce the same conflict but this time leave the repo mid-rebase
for you to actually fix it. Confirmed by running `gh stack rebase` right after a `sync`
conflict in the same fixture: it re-hit the identical conflict, printed `Conflicted
files:` with the affected path, and left `git status` mid-rebase with that file listed
under "Unmerged paths" — the state where `git add` then `gh stack rebase --continue`
(or `--abort`) actually applies.

When `rc == 3` for a repo:

1. **Stop processing that repo — do not touch it further.** Do not attempt automatic
   conflict resolution of any kind, and do not run `gh stack rebase` on the user's behalf
   — handing off means telling them the next command, not running it.
2. Print `$out` verbatim — it already names the branch and reports that all branches were
   restored.
3. Follow it with the accurate two-step handoff, since `sync`'s own message stops short of
   the `git add` / `--continue` detail:
   ```
   <repo>: rebase conflict — sync stopped and restored all branches (working tree is
   clean, nothing to resolve on disk yet).
   To resolve:
     1. cd <repo> && gh stack rebase
        (this reproduces the conflict interactively and lists the conflicted files)
     2. Fix the conflicts it reports
     3. git add <resolved files>
     4. gh stack rebase --continue
   Or, once inside that interactive rebase, abort it with: gh stack rebase --abort
   ```
4. Record this repo's status as **conflicted** for the summary (Step 4) and move on to
   the next repo — a conflict in one repo must not stop the others from syncing.

### Step 3: The divergence path (exit code 0, but nothing happened)

**This is the trap this command exists to catch.** Per `gh stack sync --help`: in a
non-interactive terminal, a diverged local/remote stack aborts the sync **with exit code
0** and nothing pushed or updated. **True divergence remains upstream-documented, not
locally observed** — it means the stack object linked on GitHub disagrees with the local
stack (e.g. someone added a PR to the stack on github.com), which needs a real GitHub
Stack object to reproduce; a local bare repo used as `origin` gives real fetch/push/PR-sync
mechanics but no GitHub Stack API, so this exact scenario and its exact abort wording are
still unconfirmed. A caller that only checks `$rc -eq 0` will misreport it as success.

Detect it with two independent signals, since the exact abort wording is not confirmed:

1. **Output keywords (best-effort, unconfirmed wording):** if `$out` matches
   `diverg|abort|cancel` (case-insensitive), treat it as diverged.
2. **State re-check (confirmed field and confirmed reliable — the signal to actually trust):**
   `needsRebase` is always present on every branch in `gh stack view --json`
   (`docs/gh-stack-json-reference.md`), and its behavior was directly confirmed in a
   local-bare-remote fixture: it flips to `true` as soon as the trunk moves, a genuinely
   completed `gh stack sync --prune` cascade clears it back to `false` on every branch
   (observed live: `✓ Rebased layer1 onto main` / `✓ Rebased layer2 onto layer1`, then
   `needsRebase: false` on both), and it stays `true` when a sync fails instead (confirmed
   in the exit-3 conflict case, Step 2). So after any `rc == 0` sync, check the freshly
   re-read stack:
   ```bash
   post=$(gh stack view --json 2>/dev/null)
   still_needs_rebase=$(jq -r '[.branches[].needsRebase] | any' <<<"$post")
   ```
   If `still_needs_rebase` is `true`, the sync did not actually finish its job — treat
   this as diverged/failed regardless of `$rc` or whether the keyword check fired. Do
   **not** rely on scanning `$out` for push/rebase activity words instead of this field —
   confirmed live, `gh stack sync` prints "Pushing N branch(es) to origin..." /
   "✓ Pushed N branches" unconditionally on every run, including one where nothing had
   changed (a true no-op push), so output text alone cannot distinguish "did real work"
   from "had nothing to do." `needsRebase` can.

If either signal fires, report this repo as **diverged**, not synced:

```
<repo>: sync reported success but the stack is still out of sync (diverged / aborted
non-interactively) — nothing was pushed or updated. Re-run in an interactive terminal to
resolve the divergence (use the remote as source of truth, or delete and resubmit).
```

Only treat a repo as **synced** when `rc == 0`, no divergence keyword matched, and no
branch still reports `needsRebase: true`.

Any other nonzero `$rc` (not 3, not the divergence case) is a plain failure — report `$out`
and record the repo as **error**.

### Step 4: Continue across repos, then summarize

A failure in one repo (conflicted, diverged, or error) must never abort the loop — every
target repo gets attempted. After all target repos have been processed, print a per-repo
summary:

```
| Repo | Result | Notes |
|------|--------|-------|
| repo-alpha | synced | pruned: <branch-list or none> |
| repo-beta | synced | nothing to do |
| repo-gamma | conflicted | see resolve instructions above |
| repo-delta | diverged | re-run interactively to resolve |
```

For a **synced** repo, the Notes column has two distinct values, and Step 5 is what
derives which one applies — a synced repo is not automatically "nothing to do." A repo
where a real cascade rebase and push happened, but `--prune` had nothing to delete, still
reads `pruned: none`, not `nothing to do`; those are different facts. See Step 5's rule.

For **conflicted** / **diverged** / **error** repos, Notes is the reason already recorded
in Step 2 / Step 3.

### Step 5: Prune the manifest, and derive each synced repo's Notes value

Skip the manifest-writing part of this step in single-repo mode — there is no manifest.
The Notes-derivation rule below still applies in single-repo mode (it only needs `$before`,
`$before_needs`, and `$after` from Step 1, not the manifest).

For a repo whose sync reached **synced** status (Step 3), compare `$before` and `$after`
(from Step 1) to find branches `--prune` deleted locally:

```bash
pruned=$(comm -23 <(sort <<<"$before") <(sort <<<"$after"))
```

**Notes derivation (confirmed against both real outcomes in a fixture — see the report):**

```bash
if [ "$before_needs" = "false" ] && [ -z "$pruned" ]; then
  note="nothing to do"
else
  note="pruned: ${pruned:-none}"
fi
```

Do **not** derive this from scanning `$out` for rebase/push activity text — confirmed live
(Step 3) that `gh stack sync` prints its "Pushing N branch(es)..." / "✓ Pushed N branches"
lines unconditionally, even on a true no-op push, so that text can't tell "real work
happened" apart from "there was nothing to do." `$before_needs` (whether any branch needed
rebasing *before* this sync ran, captured in Step 1) is the reliable signal instead: if
nothing needed rebasing and nothing got pruned, the sync had no cascade, push, or prune
work to do beyond confirming the stack already matched trunk and the remote — that's
`nothing to do`. Otherwise real work happened (a cascade rebase, a real push, or a prune),
so report it as `pruned: <branch-list or none>`, using literal `none` when work happened
but nothing was pruned.

For each branch name in `$pruned` (multi-repo mode only), apply the drop-a-branch snippet
from `docs/stacked-pr-workflow.md#manifest-writes` with `$r` = this repo's directory name
and `$b` = the branch name, so the manifest stops pointing at a branch that no longer
exists locally. Do this for every synced repo before printing the Step 4 summary. A
conflicted or diverged repo prunes nothing (its `$before`/`$after` diff is empty, since
`--prune` runs after the push step that never happened) and gets no Notes derivation here
— its Notes value already came from Step 2 or Step 3.

## Rules

- NEVER fall back to a hand-rolled `git rebase` chain if `gh stack` is unavailable — stop
  instead (see Preflight).
- NEVER attempt automatic conflict resolution, and never run `gh stack rebase` (or
  `--continue`/`--abort`) on the user's behalf. On exit code 3, stop that repo, report
  that `sync` already restored all branches, and hand off the `gh stack rebase` →
  resolve → `git add` → `--continue` (or `--abort`) sequence to the user (Step 2).
- NEVER trust `$rc -eq 0` alone as success — always re-check `needsRebase` on that repo's
  stack afterward (Step 3). This is the single most important behavior in this command.
- NEVER derive the synced-repo Notes value ("nothing to do" vs. "pruned: ...") from
  scanning `$out` for push/rebase activity text — `gh stack sync` prints its push lines
  unconditionally even on a true no-op. Use `$before_needs` and `$pruned` instead (Step 5).
- A failure in one repo (conflicted, diverged, or error) MUST NOT stop the loop for the
  rest — every target repo is attempted, and the summary (Step 4) reports all of them.
- The manifest stores branches, never PR numbers. Prune only drops branch entries (Step
  5); it never touches PR data because the manifest never had any.
- `rc == 2` from `gh stack view --json` means "no stack in this repo" — skip and report,
  not an error.
- Retargeting after merge is this command's job, via `gh stack sync` — never hand-roll a
  `gh pr edit --base` call for it (that belongs to no command in this workflow; `sync`
  does it as part of reconciling the remote stack).
