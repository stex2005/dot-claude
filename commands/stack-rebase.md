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

before=$(gh stack view --json 2>/dev/null | jq -r '.branches[].name')
out=$(gh stack sync --prune 2>&1); rc=$?
after=$(gh stack view --json 2>/dev/null | jq -r '.branches[].name')
```

`rc_check == 2` means "no stack in this repo" — record it and move on, not an error, per
the guard's contract (same rule `/stack-status` and `/stack-checkout` use). Capture `$out`
(both stdout and stderr), `$rc`, `$before`, and `$after` for every repo that has a stack —
Steps 2, 3, and 5 all need them, and `$rc` alone is not sufficient to determine success
(Step 3).

### Step 2: The conflict path (exit code 3)

Exit code 3 means a rebase conflict — confirmed locally with `gh stack rebase` in a
fixture (see below) and consistent with `gh stack sync --help`'s own account ("If a
rebase conflict is detected, all branches are restored... you are advised to run `gh
stack rebase` to resolve conflicts interactively"). `gh stack sync`'s cascade-rebase step
uses the same rebase engine as `gh stack rebase`, so the conflict output shape is expected
to match, but this was corroborated through `gh stack rebase` directly — a remote-less
fixture cannot reach `sync`'s cascade-rebase step, since `sync` fails earlier at the fetch
step with no remote configured. Treat the exit-3 contract as solid; treat the exact
wording below as representative, not byte-for-byte guaranteed.

When `rc == 3` for a repo:

1. **Stop processing that repo — do not touch it further.** Do not attempt automatic
   conflict resolution of any kind.
2. Print `$out` verbatim — it already lists the conflicted files (observed shape:
   `Conflicted files:` followed by one `C <path>` line per file) and gh-stack's own
   resolve instructions.
3. Follow it with an explicit instruction, in case the captured output is trimmed or its
   wording drifts in a future `gh-stack` release:
   ```
   <repo>: rebase conflict — stopped.
   To resolve:
     1. Fix the conflicts listed above in <repo>
     2. git add <resolved files>
     3. gh stack rebase --continue
   Or abort and restore all branches: gh stack rebase --abort
   ```
4. Record this repo's status as **conflicted** for the summary (Step 4) and move on to
   the next repo — a conflict in one repo must not stop the others from syncing.

### Step 3: The divergence path (exit code 0, but nothing happened)

**This is the trap this command exists to catch.** Per `gh stack sync --help`
(upstream-documented, not locally observed — reproducing it needs a real diverged remote,
which the no-remote fixture constraint rules out): in a non-interactive terminal, a
diverged local/remote stack aborts the sync **with exit code 0** and nothing pushed or
updated. A caller that only checks `$rc -eq 0` will misreport this as success.

Detect it with two independent signals, since the exact abort wording is not confirmed:

1. **Output keywords (best-effort, unconfirmed wording):** if `$out` matches
   `diverg|abort|cancel` (case-insensitive), treat it as diverged.
2. **State re-check (confirmed field, the reliable signal):** `needsRebase` is always
   present on every branch in `gh stack view --json`
   (`docs/gh-stack-json-reference.md`). A sync that genuinely completed leaves no branch
   needing rebase. So after any `rc == 0` sync, check the freshly re-read stack:
   ```bash
   post=$(gh stack view --json 2>/dev/null)
   still_needs_rebase=$(jq -r '[.branches[].needsRebase] | any' <<<"$post")
   ```
   If `still_needs_rebase` is `true`, the sync did not actually finish its job — treat
   this as diverged/failed regardless of `$rc` or whether the keyword check fired.

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

### Step 5: Prune the manifest

Skip this step in single-repo mode — there is no manifest.

For a repo whose sync reached **synced** status (Step 3), compare `$before` and `$after`
(from Step 1) to find branches `--prune` deleted locally:

```bash
pruned=$(comm -23 <(sort <<<"$before") <(sort <<<"$after"))
```

For each branch name in `$pruned`, apply the drop-a-branch snippet from
`docs/stacked-pr-workflow.md#manifest-writes` with `$r` = this repo's directory name and
`$b` = the branch name, so the manifest stops pointing at a branch that no longer exists
locally. Do this for every synced repo before printing the Step 4 summary's "pruned:"
column. A conflicted or diverged repo prunes nothing (its `$before`/`$after` diff is
empty, since `--prune` runs after the push step that never happened) — no special-casing
needed beyond computing the diff.

## Rules

- NEVER fall back to a hand-rolled `git rebase` chain if `gh stack` is unavailable — stop
  instead (see Preflight).
- NEVER attempt automatic conflict resolution. On exit code 3, stop that repo, print the
  conflicted files, and hand off to the user (Step 2).
- NEVER trust `$rc -eq 0` alone as success — always re-check `needsRebase` on that repo's
  stack afterward (Step 3). This is the single most important behavior in this command.
- A failure in one repo (conflicted, diverged, or error) MUST NOT stop the loop for the
  rest — every target repo is attempted, and the summary (Step 4) reports all of them.
- The manifest stores branches, never PR numbers. Prune only drops branch entries (Step
  5); it never touches PR data because the manifest never had any.
- `rc == 2` from `gh stack view --json` means "no stack in this repo" — skip and report,
  not an error.
- Retargeting after merge is this command's job, via `gh stack sync` — never hand-roll a
  `gh pr edit --base` call for it (that belongs to no command in this workflow; `sync`
  does it as part of reconciling the remote stack).
