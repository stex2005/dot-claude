---
description: Show a dashboard of step branches grouped by logical step across repos, with PR number/state, current-branch position, and working-tree cleanliness.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *), Bash(mv *), Read, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: repo name to restrict the dashboard to a single repo — multi-repo mode only, see Step 0)

## Preflight

Run the guard block from `~/.claude/docs/stacked-pr-workflow.md#guard` and stop immediately
if it fails. `gh stack view --json` is the only supported source of branch/step data — never
fall back to hand-rolled `git branch --list '*/step*'` globbing, even if the guard fails.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`~/.claude/docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is
read only when `MODE=multi`; in single-repo mode `gh stack view --json` alone is the source
of truth and Steps 2–3 below (manifest join, reconstruction) do not apply.

This command is **read-only**, with one exception: the confirmed manifest reconstruction
in Step 5. It must never write the manifest without an explicit user confirmation.

## Your task

Show a comprehensive, per-logical-step status dashboard for the stacked branch workflow.

### Step 0: Resolve repo filter (multi-repo mode only)

If `$ARGUMENTS` is provided, resolve it against `repos()`: try an exact match first, then
a substring match against subdirectory names — the same convention `/stack-commit` uses
in its Step 0 for resolving a repo argument. If it resolves, restrict `repos()` to that
one repo for the rest of this run, so every later step (collection, join, dashboard) only
ever considers that repo. If nothing matches, report the available repos (from `repos()`)
and stop.

In single-repo mode there is only one repo to show, so `$ARGUMENTS` is not a repo selector
— ignore it.

### Step 1: Collect each repo's stack state

**Single-repo mode:** Run once, in the current directory:

```bash
gh stack view --json 2>/dev/null
rc=$?
git status --porcelain
```

If `rc` is `2`, there is no stack here — report "no stack" and stop; this is not an error.
If `rc` is `6`, the checked-out branch belongs to **several** stacks (typically trunk in a
repo holding more than one) — report `on <branch>, which belongs to multiple stacks —
check out a non-trunk branch of the intended stack and re-run` and stop; also not a
generic failure, per `~/.claude/docs/stacked-pr-workflow.md#exit-codes`. Any other
non-zero exit is a real failure — report it and stop. Keep the `git status --porcelain`
output (empty = clean) alongside the JSON; Step 4 needs it for the
working-tree-cleanliness column.

**Multi-repo mode:** For each repo from `repos()` (as filtered by Step 0), run inside
that repo (`cd "$WS/$repo"`):

```bash
gh stack view --json 2>/dev/null
rc=$?
git status --porcelain
```

Again, `rc == 2` means "no stack in this repo" — record that and move on to the next repo
rather than treating it as an error; a repo can legitimately sit outside the current stack
(see the "not in this step" row in Step 4). `rc == 6` means that repo's current branch
belongs to **several** stacks — record it as `multiple stacks — check out a non-trunk
branch of the intended stack and re-run`, list it beside the no-stack repos in Step 4, and
move on; it is not a generic failure either
(`~/.claude/docs/stacked-pr-workflow.md#exit-codes`). Collect each repo's parsed JSON, its
`git status --porcelain` output, and its no-stack / multiple-stacks status (if any) before
moving to the join. `.currentBranch` from the JSON and the porcelain output together give,
per repo, which branch is checked out right now and whether that checkout is dirty — the
two facts Step 4 needs to mark "current position" and cleanliness.

### Step 2: Determine step numbers per repo

**Single-repo mode:** There is no manifest. The step number for a branch is its **1-indexed
bottom-first position** in `.branches` from Step 1's output — identical to the rule
`/stack-commit` uses in its Step 1
(`~/.claude/docs/stacked-pr-workflow.md#manifest-schema` describes the array ordering).
There is no cross-repo join to do.

**Multi-repo mode:** If `$MANIFEST` exists, step numbers and titles come from it — read
`.steps[].n`, `.steps[].title`, and `.steps[].branches` via the manifest-read snippets in
`~/.claude/docs/stacked-pr-workflow.md#manifest-reads`. If `$MANIFEST` is absent, go to Step
5 (reconstruction) before producing any output.

### Step 3: Join manifest steps against each repo's `gh stack view --json`

For each step `n` in the manifest, for each repo in `.steps[] | select(.n==$n) | .branches`:

1. Look up the branch name recorded for that repo at that step (manifest read).
2. In that repo's `gh stack view --json` output from Step 1, find the matching entry by
   name:
   ```bash
   jq -r --arg b "$branch" '.branches[] | select(.name==$b)' <<<"$repo_json"
   ```
3. Read `isMerged`, `isQueued`, `needsRebase` — always present, per
   `~/.claude/docs/gh-stack-json-reference.md`.
4. Read the PR fields with the omitted-key guard from
   `~/.claude/docs/gh-stack-json-reference.md` — **never** assume `pr` exists; a branch
   that hasn't been submitted has no `pr` key at all, not a null one:
   ```bash
   jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.number // "—"' <<<"$repo_json"
   jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.state  // "—"' <<<"$repo_json"
   ```
   If the branch itself can't be found in that repo's `.branches` (e.g. it was renamed
   outside the manifest, or the repo reported "no stack" in Step 1), show it as unresolved
   rather than crashing — note it plainly in the row instead of a PR/state value.
5. If a repo has **no entry** in `.steps[$n].branches` at all, it is not participating in
   that step — render its row as `(not in this step)`, per Step 4's format. Do this for
   every workspace repo, not just the ones the manifest happens to mention, so a repo that
   never joined the stack still shows up once per step.

### Step 4: Print the dashboard

**Multi-repo mode**, grouped by step, one block per step, all workspace repos listed
within each block:

```
Step 2 — Extract gripper class
  unloading_robot_ws  08-31-gripper_class   PR #412 OPEN    ⚠ needs rebase
  contoro_utils        08-31-gripper_types   PR #77  MERGED  (current) [3 uncommitted]
  cloud-platform       —                     (not in this step)
```

Rules for a row:
- Branch name from the manifest for that repo/step.
- `PR #<number> <state>` when `.pr` is present; `—` (from the `// "—"` guard) when absent
  and the branch simply hasn't been submitted yet — do not print `(not in this step)` in
  that case, only for a repo genuinely absent from `.steps[$n].branches`.
- Append `⚠ needs rebase` when `needsRebase` is true, and `⚠ queued` when `isQueued` is
  true; append `✓ merged` when `isMerged` is true instead of a PR state if you already
  know the PR merged.
- **Current position and working-tree cleanliness:** a repo only has one working tree, so
  these facts attach to whichever row's branch equals that repo's `.currentBranch` from
  Step 1 — append `(current)`, then `[clean]` or `[N uncommitted]` from that repo's `git
  status --porcelain` line count (0 lines = clean). Rows for a repo's other steps carry no
  cleanliness marker — you are not checked out there, so there is nothing to report.
- **When `.currentBranch` matches no row** — this is a real, measured case, not a
  defensive hypothetical: with trunk checked out, `gh stack view --json` reports
  `"currentBranch": "main"` while `.branches` holds only the stack's layer branches
  (`~/.claude/docs/gh-stack-json-reference.md`), and `gh stack sync --prune` produces it
  routinely by moving your checkout off a pruned branch. Do **not** silently drop the
  marker. Print it as its own line under that repo's step rows instead:
  ```
    unloading_robot_ws  (current: main — not a step branch) [clean]
  ```
  Use the same `[clean]` / `[N uncommitted]` suffix, and say `not a step branch` when
  `.currentBranch` equals `.trunk`, or `not in this stack` when it is neither trunk nor a
  branch in `.branches`. The MUST in the Rules below is satisfied by this line: every repo
  with a stack reports its current position and cleanliness exactly once, either on a step
  row or on this fallback line.
- A non-participating repo gets `—` for branch and `(not in this step)` verbatim, with no
  PR/state/current/cleanliness columns.

**Single-repo mode**: one flat list, no manifest grouping, step numbers from Step 2:

```
Step 1  test-layer1          —
Step 2  08-31-add_c_layer    —            (current) [clean]
```

Mark `.currentBranch` explicitly, with the same `(current) [clean]` / `(current) [N
uncommitted]` suffix as multi-repo mode, from the single `git status --porcelain` reading
in Step 1 — and with the same fallback line when `.currentBranch` matches no listed
branch (e.g. `(current: main — not a step branch) [clean]`), which is what you get with
trunk checked out. Since there is no manifest, there are no step titles and no cross-repo columns
— just branch, PR (with the same `// "—"` guard), and status flags.

If a repo reported "no stack" or "multiple stacks" in Step 1, list it under its own line
(multi-repo mode) or report it directly and stop (single-repo mode) rather than folding it
into the step table.

### Step 5: Missing-manifest reconstruction (multi-repo mode only)

If `$MANIFEST` is absent, do **not** silently proceed as if there were zero steps, and do
**not** write a manifest on your own judgment. Instead:

1. For each repo, take `gh stack view --json .branches` from Step 1. Layer index `N`
   (1-indexed, bottom-first, same rule as single-repo mode) becomes a *guessed* step `N`.
2. Render the same dashboard as Step 4, including the same `(current)` /
   `[clean]`/`[N uncommitted]` marking rule, built from this positional guess, clearly
   labeled:
   ```
   No manifest found at .stack-manifest.json — reconstructing step numbers
   positionally (layer N in each repo → step N). This WILL be wrong if any
   repo skipped a step or the stacks were built in a different order.

   Step 1 (guessed)
     repo-alpha   08-31-layer_one   —
     repo-beta    08-31-layer_a     —
   Step 2 (guessed)
     repo-alpha   08-31-layer_two   —
     repo-beta    —                 (not in this step)
   ```
3. State plainly that this is a guess and ask the user to confirm before writing anything.
4. Only if the user explicitly confirms, write the manifest using the create snippet in
   `~/.claude/docs/stacked-pr-workflow.md#manifest-writes` (trunk per repo from `.trunk` in each
   repo's `gh stack view --json`; `name` and `plan` asked from the user, since neither is
   recoverable from `gh stack` state) followed by the record-a-branch snippet once per
   guessed step/repo pair. If the user declines or does not confirm, leave `$MANIFEST`
   untouched and end the report with the guess still shown, unwritten.

## Rules

- This is a **read-only** command, except for the one confirmed reconstruction write in
  Step 5. Never write the manifest without an explicit confirmation.
- Never fall back to `git branch --list '*/step*'` or any other hand-rolled branch
  discovery — `gh stack view --json` is the only source, per the guard.
- Exit code 2 from `gh stack view` means "no stack" for that repo, and exit code 6 means
  its current branch belongs to multiple stacks — neither is an error; both are reported
  and skipped (`~/.claude/docs/stacked-pr-workflow.md#exit-codes`).
- Every read of `.pr` must tolerate the key being entirely absent (`// "—"` or
  `// empty`), never assume it is present or null.
- Every repo's dashboard row set MUST include its current-branch position and
  working-tree cleanliness (`(current)` plus `[clean]`/`[N uncommitted]`) — this is a
  required part of the output in both modes, not an optional nicety. When `.currentBranch`
  is not one of the repo's step branches (trunk checked out, or a branch outside the
  stack), that requirement is met by the standalone `(current: <branch> — not a step
  branch)` line from Step 4, never by omitting the marker.
- If `$ARGUMENTS` names a repo (multi-repo mode), the dashboard is restricted to that
  repo per Step 0 — never silently ignore it.
- Show repos alphabetically within each step block.
