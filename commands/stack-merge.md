---
description: Merge a stack up to a chosen step across repos, with preview and confirmation.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *), Bash(mv *), Read
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

Run the guard block from `~/.claude/docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack merge` is the only supported mechanism for merging a stack — **never**
fall back to hand-rolled `gh pr merge` calls per branch, even if the guard fails. A silent
fallback would merge PRs outside `gh stack`'s own bookkeeping (retargeting, the
all-or-nothing chain) and could merge branches out of order.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`~/.claude/docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is read
(and, for marking steps merged, written) only when `MODE=multi`. In single-repo mode
there is no manifest: `gh stack`'s own `.git/gh-stack` state (in particular `isMerged`)
is sufficient, and Step 7 below does not apply.

**The manifest stores branches, never PR numbers** (per
`~/.claude/docs/stacked-pr-workflow.md#manifest-schema`). Every PR number this command uses is
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
```

Then fill `$repos_for_step` with the **repos-participating-in-step-n** snippet from
`~/.claude/docs/stacked-pr-workflow.md#manifest-reads`, run with `$n` = `N`. If it comes
back empty, print `Step $N is not recorded in the manifest — nothing to merge.` and stop.

For each repo in `$repos_for_step`, resolve `$branch` with the
**branch-recorded-for-step-n** snippet from the same section, run with `$r` = the repo's
directory name and `$n` = `N`. **Do not retype either snippet from memory** — copy them
from that section. A retyped manifest read in a sibling command shipped with `$N` where
the snippet has `$n`, which is a jq *compile* error, not a lookup miss: the capture comes
back empty and the command confidently reports that no repo participates in the step.
Here that class of bug would silently shrink a destructive command's merge set.

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
`$branch`, guarded with `// empty` per `~/.claude/docs/gh-stack-json-reference.md` — `.pr` is
omitted entirely, not null, when no PR exists yet, and the `pr` object's key names
(`number`, `state`, `url`) are inferred from struct tags, **not confirmed against a live
PR** (`~/.claude/docs/stacked-pr-workflow.md#manifest-schema`, `~/.claude/docs/gh-stack-json-reference.md`).
Every read below must tolerate the key being absent or wrong, degrading rather than
breaking:

```bash
repo_json=$(gh stack view --json 2>/dev/null); rc=$?   # run inside the repo
if [ "$rc" -eq 2 ]; then
  echo "$repo: no stack — dropping from the merge set"; continue
elif [ "$rc" -eq 6 ]; then
  echo "$repo: on $(git branch --show-current), which belongs to multiple stacks — check out a non-trunk branch of the intended stack and re-run; dropping from the merge set"
  continue
elif [ "$rc" -ne 0 ]; then
  gh stack view --json   # re-run unredirected so the user sees gh's own error
  echo "$repo: gh stack view failed (exit $rc) — stopping"; exit 1
fi
pr=$(jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.number // empty' <<<"$repo_json")
pr_state=$(jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.state // "unknown"' <<<"$repo_json")
top_branch=$(jq -r '.branches[-1].name // empty' <<<"$repo_json")
```

Exit codes 2 and 6 drop that repo from the merge set with the message shown and are
reported in the preview — never treated as generic failures, and never silently merged
past (`~/.claude/docs/stacked-pr-workflow.md#exit-codes`). `$top_branch` is the topmost
(furthest-from-trunk) branch in this repo's stack; Step 5 needs it to decide whether an
unambiguous no-argument merge is possible.

If `$pr` is empty, that repo's step-`N` branch has not been submitted (no PR yet) —
**report it and drop that repo from the merge set. Do not stop the whole command for
it.** This is the "skip, don't guess" rule: a repo with no PR for this step is never
merged by accident.

Keep, per repo: `$branch`, `$pr`, `$pr_state`, `$top_branch`, the list of branches
**above** `$branch` in `.branches`, and this repo's `repo_json` (Step 5 needs a fresh copy
again after merging, but this pre-merge one is needed for the preview and for the
over-merge check).

### Step 3: Merge method and known caveats (state these in the preview, Step 4)

This command merges with **squash** as its fixed default; there is no flag to choose
`merge` or `rebase` instead. `--squash` and `--yes` are both real flags (confirmed in
`gh stack merge --help`). The `--yes` flag skips `gh stack merge`'s own interactive
confirmation prompt — that is safe here specifically because Step 4's
preview-and-confirmation gate already obtained the user's explicit approval before this
command ever calls `gh`. **How the merge is invoked — with or without a positional number
— is decided per repo in Step 5, and that decision is load-bearing.** Read the next
subsection before writing the preview.

Two behaviors below are **documented, not locally measured** — nothing about a live merge
can be measured in this environment (Step 7's live verification is deferred). State both
in the preview:

- **All-or-nothing is per repo, not across the workspace.** Per `gh stack merge --help`:
  all members of the stack up to and including the chosen PR are merged "in a single,
  all-or-nothing operation: if any PR cannot be merged, none are"; "only basic pull
  request state is checked before merging (open and not a draft)"; GitHub evaluates
  branch protection and repository rules at merge time, and "bypassing merge requirements
  is not supported for stacks." That guarantee is scoped to **one repo's stack** — it says
  nothing about several repos, so repo A's stack can merge completely while repo B's
  fails on branch protection or a failing check. The cross-repo half is this command's
  own inference from that scope, not an upstream claim.
- **Merge queues change the outcome.** Per `gh stack merge --help`: "If the base branch
  uses a merge queue, the stack is added to the queue and merges once the queue processes
  it; otherwise it is merged directly." The finer details — that the queue picks the merge
  method so `--merge-method`/`--squash` is **ignored with a warning**, and that the PRs
  may land in **separate groups** rather than together — come from the github/gh-stack
  README, not the help output. Either way a repo in this state will not show as merged
  immediately after this command returns; Step 6 must report it as queued, not merged,
  until confirmed otherwise.

#### A bare number is read as a **stack number first** — this is documented, not a maybe

`gh stack merge --help` states it outright:

> With no argument, the stack for the current branch is used. Pass a stack number to
> merge a stack you don't have checked out, or a pull request number to merge directly up
> to that PR. **A bare number is treated first as a stack number, then as a pull request
> number.**

`Usage: gh stack merge [<stack-number> | <pr-number>]`. There is no flag to force the
pull-request interpretation. So `gh stack merge 7` in a repo that happens to have a stack
numbered 7 merges **stack 7 in its entirety** — not "everything up to PR #7" — even
though this command resolved 7 as a PR number and the user confirmed a preview describing
that PR. Young repos have low PR numbers and low stack numbers at the same time, so this
is the common case, not a corner case, and the damage is an unrequested merge of real PRs.

Two consequences, both mandatory:

1. **Prefer an invocation with no positional number** wherever the semantics allow it —
   see Step 5. With no argument, `gh stack merge` acts on the stack of the *current
   branch*, which cannot be misread as a stack number at all.
2. **When a number must be passed, say so in the preview and re-confirm** — see Step 4.

The rest of Step 3's caveats (all-or-nothing scope, merge queues) remain
upstream-documented rather than locally measured. This one is not a caveat: it is
documented behavior, and the command is built around it.

### Step 4: Preview and confirm — mandatory, no skip

**Before any `gh stack merge` call, show the user exactly what will merge and wait for
explicit confirmation.** This gate is not optional and has no flag to skip it, in any
mode — at least as strong a requirement as `/stack-create-pr`'s equivalent gate, and
stronger in one respect: because this action merges code, require the user to type the
literal word `yes` (not `y`/Enter) to proceed. Anything else — `n`, empty input, or
anything ambiguous — is a decline. **Do not proceed on ambiguity.**

First classify each confirmed repo's invocation, exactly as Step 5 will run it:

- **`no-arg`** — this repo's step-`N` branch **is** `$top_branch` (the topmost branch in
  its stack). Merging "up to N" and "merge the whole stack" are then the same thing, so
  Step 5 **checks that branch out** and runs `gh stack merge --yes --squash` with **no
  positional number**. Nothing can be misread as a stack number. This is the preferred
  form. It does move the repo's checkout, so say which branch each `no-arg` repo will be
  moved to in the preview, and skip any repo whose tree is dirty rather than checking out
  over it.
- **`by-pr`** — step `N` is **not** the top of this repo's stack, so branches above it
  must not merge and the PR number has to be passed. Per Step 3, `gh stack merge $pr`
  will be interpreted as **stack `$pr` first**. This must be named in the preview and
  re-confirmed.

Present:

```
About to merge up to step N ("<title>"):

  unloading_robot_ws
    step 2  08-31-gripper_class   PR #413  OPEN
            top of this repo's stack → `gh stack merge --yes --squash` on that branch
            (no number passed — unambiguous)
  contoro_utils
    step 2  08-31-gripper_types   PR #77   OPEN
            NOT the top of this repo's stack (08-31-followup sits above it)
            → `gh stack merge 77 --yes --squash`
            ⚠ 77 is passed as a PR number, but gh stack merge reads a bare number as a
              STACK number first and only then as a PR number. If contoro_utils has a
              stack numbered 77, this merges that whole stack instead of PR #77.

Not part of step N (left untouched):
  cloud-platform

Skipped — no stack / ambiguous stack / no PR yet:
  <repo>  <reason>  step N branch <branch>

Merge method: squash (fixed default for this command)

IMPORTANT:
- Repos merged by the no-number form are CHECKED OUT to the branch shown first. Their
  working trees must be clean; a dirty repo is skipped, not forced.
- This merges each repo's stack up to and including the PR shown, as one all-or-nothing
  operation PER REPO. There is no atomicity across repos — one repo can succeed while
  another fails (e.g. on branch protection).
- If a repo's base branch uses a merge queue, its PRs are queued instead of merged
  directly, the merge method above is ignored for it, and its PRs may land separately.
- Declining below leaves every PR open and merges nothing, in any repo.

Type "yes" to merge the PRs listed above, or anything else to cancel:
```

Show the `⚠` block for **every** `by-pr` repo — there is no way to check from here
whether a stack with that number exists, so the ambiguity is stated rather than tested
away. If **any** repo is `by-pr`, the single `yes` is not enough: after it, ask a second,
separate question naming those repos and their numbers —

```
<repo> (#<pr>), <repo> (#<pr>) will be merged by bare number, which gh stack reads as a
stack number first. Type "yes" again to accept that risk for these repos, "skip" to merge
only the unambiguous (no-number) repos, or anything else to cancel everything.
```

— and honour the answer: `yes` runs everything, `skip` runs only the `no-arg` repos and
reports the rest as deliberately skipped, anything else cancels the whole command.
**Never** run a `by-pr` merge on the strength of the first confirmation alone.

**Stop and wait for the literal `yes` (and, when any repo is `by-pr`, the second answer)
before proceeding to Step 5.** On anything else, report that nothing was merged and stop
— do not partially proceed with a subset of repos the user didn't explicitly re-confirm.

**`<title>`** is the step title, read with the **title-of-step-n** snippet from
`~/.claude/docs/stacked-pr-workflow.md#manifest-reads`.
In **single-repo mode there is no manifest and therefore no title source** — render the
line as `About to merge up to step N:` with no parenthetical, exactly as `/stack-status`
handles missing titles in single-repo mode. Never invent one, and never print a literal
`<title>`.

### Step 5: Merge

For each confirmed repo, in order, using the invocation classified in Step 4:

```bash
cd "$WS/$repo"   # multi-repo mode; current directory in single-repo mode

if [ "$branch" = "$top_branch" ]; then
  # no-arg: merging "up to N" == merging this whole stack, so pass no number at all.
  # gh stack merge with no argument acts on the stack of the CURRENT BRANCH, so the
  # checkout is what selects the stack — and nothing can be misread as a stack number.
  if [ -n "$(git status --porcelain)" ]; then
    echo "$repo: uncommitted changes — cannot check out $branch to merge safely; skipping"
    continue
  fi
  git checkout "$branch" || { echo "$repo: could not check out $branch; skipping"; continue; }
  out=$(gh stack merge --yes --squash 2>&1); rc=$?
else
  # by-pr: branches above step N must not merge, so the PR number has to be passed —
  # with the stack-number-first ambiguity the user re-confirmed in Step 4.
  out=$(gh stack merge "$pr" --yes --squash 2>&1); rc=$?
fi
```

The `no-arg` branch is preferred, and it is available whenever step `N` is the top of that
repo's stack — the ordinary case when merging the stack you have just finished. Do **not**
"simplify" this back to always passing `$pr`.

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

**Also check that nothing merged that shouldn't have.** For a `by-pr` repo, if the number
was read as a *stack* number the wrong thing just landed, and `$rc` will not say so. Using
the "branches above `$branch`" list captured in Step 2, look for any of them now merged in
`$post`. Call that list `$over`.

Any branch in `$over` merged despite sitting above step `N` — the stack-number-collision
outcome Step 3 warns about, or a merge queue processing more than expected. A `no-arg`
repo cannot be over-merged: by construction there is nothing above `$branch`.

Classify each repo's outcome as exactly one of:
- **merged** — `rc == 0`, `merged_now == true`, and `$over` is empty.
- **over-merged** — `$over` is non-empty: branches above step `N` merged too. Report `$out`
  verbatim, name the branches in `$over`, and say plainly that more merged than was
  previewed. Never fold this into "merged".
- **queued** — `rc == 0` and `merged_now == false` and `queued_now == true` (merge-queue
  path; not yet actually merged).
- **failed** — `rc != 0`, or `rc == 0` with neither `merged_now` nor `queued_now` true
  (an unexpected state — report `$out` verbatim rather than guessing what happened).

### Step 6: Report partial success honestly

Print a per-repo table. **Never claim workspace-wide success unless every target repo's
outcome is `merged`** — `over-merged` is not success.

```
| Repo               | Branch                | PR   | Result  | Notes                          |
|--------------------|------------------------|------|---------|---------------------------------|
| unloading_robot_ws  | 08-31-gripper_class    | #413 | merged  |                                 |
| contoro_utils       | 08-31-gripper_types    | #77  | failed  | branch protection — see output |
```

If every row is `merged`: "Step N merged in every participating repo."
If any row is `over-merged`: lead with it. Name the repo, the branches above step `N` that
merged anyway, and the likely cause (the bare number read as a stack number, per Step 3;
or a merge queue taking more than expected). This is not recoverable from inside this
workflow, so it must never be reported as success.
If any row is `failed` or `queued`: state plainly that this is a **partial** result —
name which repos merged and which didn't, and for `failed` rows include `$out`. For
`queued` rows, say the PR is in the base branch's merge queue and not yet actually
merged — re-run `/stack-status` or check the PR later to confirm.

Also restate, from Steps 1 and 2: repos not part of step N (untouched), and repos skipped
for having no stack, an ambiguous stack, or no PR yet.

### Step 7: Mark merged in the manifest (multi-repo mode only)

Skip this step entirely in single-repo mode — there is no manifest; `gh stack`'s own
`isMerged` already reflects merge status.

The manifest's `steps[].merged` flag is a single boolean per step, **not per repo**
(`~/.claude/docs/stacked-pr-workflow.md#manifest-schema`). Because a step can list several repos,
writing this flag needs its own honesty check beyond "did this run's Step 5 succeed for
step N": a repo that isn't part of step N was never touched by this run at all, and an
earlier step could in principle still be unmerged in some repo even though this run only
targeted `N`. So before writing anything, verify live, for every step `m` from `1` to
`N`, that **every repo participating in step `m`** currently shows `isMerged: true`:

```bash
n_effective=0
for m in $(seq 1 "$N"); do
  ok=true
  # <repos participating in step m>: the repos-participating-in-step-n snippet from
  #   ~/.claude/docs/stacked-pr-workflow.md#manifest-reads, with $n = $m
  for r in <repos participating in step m>; do
    # <branch for $r at step m>: the branch-recorded-for-step-n snippet from the same
    #   section, with $r = "$r" and $n = $m
    b=<branch for $r at step m>
    j=$(cd "$WS/$r" && gh stack view --json 2>/dev/null)
    im=$(jq -r --arg b "$b" '.branches[] | select(.name==$b) | .isMerged // false' <<<"$j")
    [ "$im" = "true" ] || ok=false
  done
  if [ "$ok" = "true" ]; then n_effective=$m; else break; fi
done
```

Fill the two placeholders by copying the snippets from
`~/.claude/docs/stacked-pr-workflow.md#manifest-reads` — do not retype them (Step 1 says
why).

This finds the longest **contiguous** prefix of steps (starting at 1) that are fully
merged in every repo that participates in them, capped at the requested `N`. Re-querying
`gh stack view --json` here (rather than trusting Step 5's outcome table) is what makes
this correct for a repo that wasn't part of step `N` at all, or for a step that was
already merged by an earlier `/stack-merge` run.

If `n_effective > 0`, apply the canonical "mark every step up to and including n as
merged" snippet from `~/.claude/docs/stacked-pr-workflow.md#manifest-writes`, with `$n =
n_effective`. If `n_effective == 0` (step 1 itself isn't fully merged across its
repos yet — e.g. this run's only target repo failed), **write nothing** and say so in the
summary.

Only repos that actually succeeded ever contribute to `n_effective` reaching a given
step — a repo with a `failed` or `queued` outcome at step `N` (or any step below it that
it participates in) blocks that step, and every step above it, from being marked.

### Step 8: Final summary

Close with:

```
Requested: merge up to step N ("<title>" — omit the parenthetical entirely in
           single-repo mode, where there is no manifest and so no title)
Checkouts moved: <repo → branch, for each no-number repo | none>
Result: <"fully merged" | "OVER-MERGED — see above" | "PARTIAL — see table above">
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
- Every unmeasurable claim about `gh stack merge`'s behavior (all-or-nothing scope, merge
  queue handling) is documented rather than locally measured — say so, per the discipline
  `/stack-create-pr` and `/stack-rebase` established. Attribute each to the right source:
  `gh stack merge --help` for the all-or-nothing wording, the merge-queue fallback, and
  the argument precedence; the github/gh-stack README for the merge-queue method/grouping
  details; this command itself for the cross-repo (non-)atomicity inference.
- **A bare number passed to `gh stack merge` is read as a stack number first, then as a
  PR number** — documented in `gh stack merge --help`, not a hypothetical. Prefer the
  no-argument form (check the step's branch out; only valid when it is the top of that
  repo's stack). When a number must be passed, name the ambiguity in the preview, take a
  second explicit confirmation, and check afterwards whether branches above step N merged
  (Step 5's `over-merged` outcome).
- Never retype a manifest jq snippet from memory — copy it from
  `~/.claude/docs/stacked-pr-workflow.md#manifest-reads` / `#manifest-writes`. This is a
  destructive command; a retyped read that silently returns empty shrinks or shifts the
  merge set.
- `<title>` comes from the manifest and does not exist in single-repo mode — omit it
  there rather than printing a placeholder.
