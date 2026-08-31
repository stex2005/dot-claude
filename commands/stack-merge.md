---
description: Merge a stack up to a chosen step across repos, with preview and confirmation.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *), Read
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (required: `stepN` or a bare `N` — the step to merge up to; see Step 0)

## This is the only destructive command in this workflow

Every other `/stack-*` command reads or rearranges local/PR state. This one merges real
PRs on GitHub, which cannot be cleanly undone from inside this workflow. Treat the
preview-and-confirmation gate in Step 4 as load-bearing: nothing in this command may call
`gh stack merge` before the user has seen the full preview and explicitly confirmed it.

## Preflight

Run the guard block from `docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack merge` is the only supported mechanism for merging a stack — **never**
fall back to hand-rolled `gh pr merge` calls per branch, even if the guard fails. A silent
fallback would merge PRs outside `gh stack`'s own bookkeeping (retargeting, the
all-or-nothing chain) and could merge branches out of order.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is read
(and, for marking steps merged, written) only when `MODE=multi`. In single-repo mode
there is no manifest: `gh stack`'s own `.git/gh-stack` state (in particular `isMerged`)
is sufficient, and Step 7 below does not apply.

**The manifest stores branches, never PR numbers** (per
`docs/stacked-pr-workflow.md#manifest-schema`). Every PR number this command uses is
resolved fresh from `gh stack view --json` on each run — it is never read from, or
written to, the manifest. This matters specifically here: PR state changes on every
merge, so a cached number would go stale immediately.

## Your task

### Step 0: Parse the target step argument

`$ARGUMENTS` is **required**, unlike most other stack commands. Match it against
`^step([0-9]+)$` or a bare `^[0-9]+$` — the same pattern `/stack-create-pr` uses in its
Step 0 for step mode. If it matches, `N` is that number. If `$ARGUMENTS` is empty or
doesn't match, report usage (`/stack-merge step<N>`) and stop — there is no default step
to merge up to, and guessing one is not acceptable for a destructive command.

### Step 1: Resolve participating repos and each one's branch for step N

**Multi-repo mode:**

```bash
if [ ! -f "$MANIFEST" ]; then
  echo "No manifest at $MANIFEST — cannot resolve step membership. Run /stack-status first."
  exit 1
fi
repos_for_step=$(jq -r --argjson n "$N" '.steps[] | select(.n==$n) | .branches | keys[]' "$MANIFEST")
if [ -z "$repos_for_step" ]; then
  echo "Step $N is not recorded in the manifest — nothing to merge."
  exit 1
fi
```

For each repo in `$repos_for_step`, resolve its branch with the exact snippet from the
brief:

```bash
branch=$(jq -r --arg r "$repo" --argjson n "$N" \
  '.steps[] | select(.n==$n) | .branches[$r] // empty' "$MANIFEST")
```

Every repo from `repos()` that is **not** in `$repos_for_step` is not participating in
step `N` — leave it untouched (same convention `/stack-checkout` uses for a repo absent
from a step) and list it in the preview (Step 4) as "not part of step N — left
untouched," not as a failure.

**Single-repo mode:** there is no manifest; resolve the branch positionally, the same
1-indexed bottom-first rule every other command uses:

```bash
json=$(gh stack view --json 2>/dev/null); rc=$?
if [ "$rc" -eq 2 ]; then
  echo "no stack here"; exit 1
fi
total=$(jq '.branches | length' <<<"$json")
if [ "$N" -lt 1 ] || [ "$N" -gt "$total" ]; then
  echo "step $N does not exist — stack has $total step(s)"; exit 1
fi
branch=$(jq -r --argjson i "$((N-1))" '.branches[$i].name' <<<"$json")
```

### Step 2: Resolve the PR for each repo's branch

For each participating repo (multi-repo: each repo in `$repos_for_step`; single-repo: the
one repo), fetch that repo's `gh stack view --json` and resolve the PR number for
`$branch`, guarded with `// empty` per `docs/gh-stack-json-reference.md` — `.pr` is
omitted entirely, not null, when no PR exists yet, and the `pr` object's key names
(`number`, `state`, `url`) are inferred from struct tags, **not confirmed against a live
PR** (`docs/stacked-pr-workflow.md#manifest-schema`, `docs/gh-stack-json-reference.md`).
Every read below must tolerate the key being absent or wrong, degrading rather than
breaking:

```bash
repo_json=$(gh stack view --json)   # run inside the repo
pr=$(jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.number // empty' <<<"$repo_json")
pr_state=$(jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.state // "unknown"' <<<"$repo_json")
```

If `$pr` is empty, that repo's step-`N` branch has not been submitted (no PR yet) —
**report it and drop that repo from the merge set. Do not stop the whole command for
it.** This is the "skip, don't guess" rule: a repo with no PR for this step is never
merged by accident.

Keep, per repo: `$branch`, `$pr`, `$pr_state`, and this repo's `repo_json` (Step 5 needs
a fresh copy again after merging, but this pre-merge one is needed for the preview).

### Step 3: Merge method and known caveats (state these in the preview, Step 4)

This command merges with `gh stack merge "$pr" --yes --squash` — **squash** is this
command's fixed default, matching the brief; there is no flag to choose `merge` or
`rebase` instead. The `--yes` flag skips `gh stack merge`'s own interactive confirmation
prompt — that is safe here specifically because Step 4's preview-and-confirmation gate
already obtained the user's explicit approval before this command ever calls `gh`.

Two behaviors below are **upstream-documented** (the github/gh-stack README's `gh stack
merge` section), not locally measured — nothing about a live merge can be locally
measured in this environment (Step 7's live verification is deferred). State both in the
preview:

- **All-or-nothing is per repo, not across the workspace.** `gh stack merge` merges all
  PRs in one repo's stack up to and including the chosen PR as a single all-or-nothing
  operation — if any PR in that repo can't be merged, none in that repo are. But there is
  **no atomicity across repos**: repo A's stack can merge completely while repo B's
  fails on branch protection or a failing check. Only basic PR state (open, not draft) is
  checked before merging; GitHub evaluates branch protection and repository rules at
  merge time, and **bypassing merge requirements is not supported**.
- **Merge queues change the outcome.** If a repo's base branch uses a merge queue, the
  stack is added to the queue instead of merging directly — the queue picks the merge
  method, so `--merge-method`/`--squash` is **ignored with a warning**, and the PRs may
  land in **separate groups** rather than together. A repo in this state will not show as
  merged immediately after this command returns; Step 6 must report it as queued, not
  merged, until confirmed otherwise.

Also flag one more upstream ambiguity, so it is not silently assumed away: `gh stack
merge` takes a single positional argument documented as `<stack-number> | <pr-number>`,
with no documented way to force which interpretation applies. This command always passes
a real PR number (never a local layer position), which is the documented alternative, but
the two numbering spaces are not confirmed to be collision-free (a low PR number on a
young repo could in principle be ambiguous with a small stack-number). This is unverified
and flagged here rather than assumed safe.

### Step 4: Preview and confirm — mandatory, no skip

**Before any `gh stack merge` call, show the user exactly what will merge and wait for
explicit confirmation.** This gate is not optional and has no flag to skip it, in any
mode — at least as strong a requirement as `/stack-create-pr`'s equivalent gate, and
stronger in one respect: because this action merges code, require the user to type the
literal word `yes` (not `y`/Enter) to proceed. Anything else — `n`, empty input, or
anything ambiguous — is a decline. **Do not proceed on ambiguity.**

Present:

```
About to merge up to step N ("<title>") via `gh stack merge <pr> --yes --squash`:

  unloading_robot_ws
    step 2  08-31-gripper_class   PR #413  OPEN  → will merge (and everything below it in this repo)
  contoro_utils
    step 2  08-31-gripper_types   PR #77   OPEN  → will merge (and everything below it in this repo)

Not part of step N (left untouched):
  cloud-platform

Skipped — no PR yet (not submitted):
  <repo>  step N branch <branch>

Merge method: squash (fixed default for this command)

IMPORTANT:
- This merges each repo's stack up to and including the PR shown, as one all-or-nothing
  operation PER REPO. There is no atomicity across repos — one repo can succeed while
  another fails (e.g. on branch protection).
- If a repo's base branch uses a merge queue, its PRs are queued instead of merged
  directly, the merge method above is ignored for it, and its PRs may land separately.
- Declining below leaves every PR open and merges nothing, in any repo.

Type "yes" to merge the PRs listed above, or anything else to cancel:
```

**Stop and wait for the literal `yes` before proceeding to Step 5.** On anything else,
report that nothing was merged and stop — do not partially proceed with a subset of
repos the user didn't explicitly re-confirm.

### Step 5: Merge

For each confirmed repo, in order:

```bash
cd "$WS/$repo"   # multi-repo mode; current directory in single-repo mode
out=$(gh stack merge "$pr" --yes --squash 2>&1); rc=$?
```

**A failure in one repo must not stop the loop** — attempt every confirmed repo, per the
per-repo (not workspace-wide) all-or-nothing rule from Step 3. Record `$out` and `$rc`
for each.

**Do not trust `$rc == 0` alone as "merged."** Immediately re-fetch that repo's stack and
check the branch's actual state — the merge-queue case (Step 3) can return success while
the PR is only queued, not yet merged:

```bash
post=$(gh stack view --json 2>/dev/null)
merged_now=$(jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .isMerged // false' <<<"$post")
queued_now=$(jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .isQueued // false' <<<"$post")
```

Classify each repo's outcome as exactly one of:
- **merged** — `rc == 0` and `merged_now == true`.
- **queued** — `rc == 0` and `merged_now == false` and `queued_now == true` (merge-queue
  path; not yet actually merged).
- **failed** — `rc != 0`, or `rc == 0` with neither `merged_now` nor `queued_now` true
  (an unexpected state — report `$out` verbatim rather than guessing what happened).

### Step 6: Report partial success honestly

Print a per-repo table. **Never claim workspace-wide success unless every target repo's
outcome is `merged`.**

```
| Repo               | Branch                | PR   | Result  | Notes                          |
|--------------------|------------------------|------|---------|---------------------------------|
| unloading_robot_ws  | 08-31-gripper_class    | #413 | merged  |                                 |
| contoro_utils       | 08-31-gripper_types    | #77  | failed  | branch protection — see output |
```

If every row is `merged`: "Step N merged in every participating repo."
If any row is `failed` or `queued`: state plainly that this is a **partial** result —
name which repos merged and which didn't, and for `failed` rows include `$out`. For
`queued` rows, say the PR is in the base branch's merge queue and not yet actually
merged — re-run `/stack-status` or check the PR later to confirm.

Also restate, from Step 1: repos not part of step N (untouched) and repos skipped for
having no PR yet.

### Step 7: Mark merged in the manifest (multi-repo mode only)

Skip this step entirely in single-repo mode — there is no manifest; `gh stack`'s own
`isMerged` already reflects merge status.

The manifest's `steps[].merged` flag is a single boolean per step, **not per repo**
(`docs/stacked-pr-workflow.md#manifest-schema`). Because a step can list several repos,
writing this flag needs its own honesty check beyond "did this run's Step 5 succeed for
step N": a repo that isn't part of step N was never touched by this run at all, and an
earlier step could in principle still be unmerged in some repo even though this run only
targeted `N`. So before writing anything, verify live, for every step `m` from `1` to
`N`, that **every repo participating in step `m`** currently shows `isMerged: true`:

```bash
n_effective=0
for m in $(seq 1 "$N"); do
  ok=true
  for r in $(jq -r --argjson n "$m" '.steps[] | select(.n==$n) | .branches | keys[]' "$MANIFEST"); do
    b=$(jq -r --arg r "$r" --argjson n "$m" '.steps[] | select(.n==$n) | .branches[$r] // empty' "$MANIFEST")
    j=$(cd "$WS/$r" && gh stack view --json 2>/dev/null)
    im=$(jq -r --arg b "$b" '.branches[] | select(.name==$b) | .isMerged // false' <<<"$j")
    [ "$im" = "true" ] || ok=false
  done
  if [ "$ok" = "true" ]; then n_effective=$m; else break; fi
done
```

This finds the longest **contiguous** prefix of steps (starting at 1) that are fully
merged in every repo that participates in them, capped at the requested `N`. Re-querying
`gh stack view --json` here (rather than trusting Step 5's outcome table) is what makes
this correct for a repo that wasn't part of step `N` at all, or for a step that was
already merged by an earlier `/stack-merge` run.

If `n_effective > 0`, apply the canonical "mark every step up to and including n as
merged" snippet from `docs/stacked-pr-workflow.md#manifest-writes`, with `$n =
n_effective`. If `n_effective == 0` (step 1 itself isn't fully merged across its
repos yet — e.g. this run's only target repo failed), **write nothing** and say so in the
summary.

Only repos that actually succeeded ever contribute to `n_effective` reaching a given
step — a repo with a `failed` or `queued` outcome at step `N` (or any step below it that
it participates in) blocks that step, and every step above it, from being marked.

### Step 8: Final summary

Close with:

```
Requested: merge up to step N ("<title>")
Result: <"fully merged" | "PARTIAL — see table above">
Manifest: <"steps 1–<n_effective> marked merged" | "not updated — see above" | "not applicable (single-repo mode)">

Next: once a repo's bottom PR has merged, run /stack-rebase there to retarget the next
PR onto trunk and prune the merged branch locally — this command does not do that itself.
```

## Rules

- **Never call `gh stack merge` (or any merge) before Step 4's typed `yes` confirmation.**
  This gate has no skip flag, in any mode.
- NEVER fall back to hand-rolled `gh pr merge` per branch if `gh stack` is unavailable —
  stop instead (see Preflight). It bypasses `gh stack`'s all-or-nothing chain and
  retargeting bookkeeping.
- The manifest stores branches, never PR numbers — resolve every PR fresh from `gh stack
  view --json` each run (Step 2), never cache one.
- A repo whose step-`N` branch has no `pr` key is reported and **skipped**, never merged.
- All-or-nothing from `gh stack merge` is **per repo, not across the workspace** — a
  failure in one repo must never stop the loop for the others (Step 5), and the summary
  (Step 6) must never claim workspace-wide success unless every target repo's outcome is
  `merged`.
- Never trust `rc == 0` alone as proof of a merge — always re-check `isMerged`/`isQueued`
  on that repo's stack afterward (Step 5), because a merge-queue repo can return success
  while only queuing the PR.
- Only mark a step `merged` in the manifest once it is **live-verified** merged in every
  repo that participates in it, using the contiguous-prefix check in Step 7 — never
  write the blanket "up to n" flag on the strength of this run's Step 5 outcomes alone.
- Do NOT add `Bash(mv *)` to `allowed-tools` — a house-wide gap deferred to Task 11, even
  though Step 7 writes the manifest via the canonical snippet's `mv`.
- Every unmeasurable claim about `gh stack merge`'s behavior (all-or-nothing scope, merge
  queue handling, the stack-number/pr-number argument) is upstream-documented, not
  locally measured — say so, per the discipline `/stack-create-pr` and `/stack-rebase`
  established.
