---
description: Restructure one repo's stack via gh stack modify, then reconcile the workspace manifest.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(mv *), Read
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: repo name — multi-repo mode only, see Step 1)

## Preflight

Run the guard block from `~/.claude/docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack modify` is the only supported mechanism for restructuring a stack —
**never** fall back to hand-rolled branch surgery (`git rebase -i`, manual branch
delete/rename), even if the guard fails. A silent fallback would restructure branches
outside `gh stack`'s own bookkeeping and would still leave the manifest unreconciled,
which is the one problem this command exists to solve.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`~/.claude/docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is read and
reconciled only when `MODE=multi`; in single-repo mode there is no manifest — `gh stack`'s
own `.git/gh-stack` state is sufficient, and Step 5 below does not apply.

**Why this command exists at all:** `gh stack modify` is an interactive, full-screen TUI,
and it is single-repo by nature — it has no concept of the workspace manifest. Left alone,
a rename or drop performed inside the TUI would silently desynchronize the manifest's
cross-repo correlation (`~/.claude/docs/stacked-pr-workflow.md#manifest-schema`) from the branches
that actually exist afterward. Reconciling that gap is this command's **only** job — Step
4 hands off to the real TUI completely unmodified; Step 5 is the entire point of wrapping
it.

## Your task

### Step 1: Resolve exactly one repo

`gh stack modify` operates on a single repo's local stack; there is no multi-repo variant
of it. This command must resolve to exactly one repo before touching anything.

**Single-repo mode:** there is no repo-name concept — operate on the current repo. Any
value in `$ARGUMENTS` is ignored.

**Multi-repo mode:** resolve `$ARGUMENTS` against `repos()` — exact match first, then
substring match against subdirectory names, the same convention `/stack-commit`,
`/stack-create-pr`, and `/stack-rebase` use in their Step 0. If it resolves to exactly one
repo, proceed with that repo. If `$ARGUMENTS` is empty, or ambiguous, or matches nothing,
**ask** which repo to restructure — list the repos from `repos()` and stop. Do not guess
(e.g. by picking "the only repo with a stack"): restructuring the wrong repo's stack is
not something this command can undo.

All subsequent steps run inside the resolved repo (`cd "$WS/$repo"` in multi-repo mode;
the current directory in single-repo mode).

### Step 2: Check preconditions

```bash
gh stack view --json >/dev/null 2>&1; rc=$?
[ "$rc" -ne 2 ] || { echo "no stack here — nothing to modify"; exit 1; }
[ "$rc" -ne 6 ] || {
  echo "on $(git branch --show-current), which belongs to multiple stacks — gh stack cannot tell which one to modify."
  echo "Check out a non-trunk branch of the stack you mean and re-run."
  exit 1
}
[ -z "$(git status --porcelain)" ] || { echo "Working tree must be clean."; exit 1; }
[ ! -d .git/rebase-merge ] && [ ! -d .git/rebase-apply ] || { echo "Rebase in progress."; exit 1; }
```

`rc == 2` means "no stack in this repo" per the exit-code contract in
`~/.claude/docs/stacked-pr-workflow.md#exit-codes`, the same rule every other stack command
uses — this covers the "an active stack checked out" precondition, which is otherwise easy
to overlook since it's the one this command's own name presumes. `rc == 6` means the
current branch is in **several** stacks, so there is no single stack to restructure;
this command is the one place where guessing is least acceptable, so it stops with the
message above rather than picking one.
The other two (clean tree, no rebase in progress) are checked here because they're cheap
to verify from outside the TUI. Two more
preconditions are **upstream-documented** (github/gh-stack README, `gh stack modify`
section), not independently checkable from a wrapper script — state them to the user
before handing off rather than silently hoping they hold:

- **Linear commit history.** `gh stack modify` expects a linear stack; it is not built to
  reconcile merge commits within it.
- **No PR in the stack queued for merge.** Modifying a stack with a PR sitting in a merge
  queue is unsupported.

If a queued PR is suspected (e.g. any branch shows `isQueued: true` in `gh stack view
--json`), warn the user about it before proceeding to Step 3 rather than handing off
blind.

### Step 3: Snapshot before the TUI

```bash
before_json=$(gh stack view --json)
before=$(jq -r '.branches[].name' <<<"$before_json")
```

Keep both `$before_json` (Step 6 needs it to know whether the stack was ever submitted)
and `$before` (Step 5's reconciliation is a diff against this name list).

### Step 4: Hand off to the TUI

Run `gh stack modify` and let the user drive it interactively — this command does not,
and cannot, script it. It is a full-screen interactive tool; per the github/gh-stack
README (**upstream-documented**, not locally verified — an interactive TUI cannot be
driven from here), its operations are: drop (`x`), fold down (`d`), fold up (`u`), insert
(`i`/`I`), reorder (Shift+↑/↓), rename (`r`), undo (`z`), apply (Ctrl+S), cancel (`q`/Esc).
Also upstream-documented: dropping a branch removes it from the stack but **preserves the
local branch and its PR**; folding absorbs a branch's commits into a neighbour and removes
it from the stack; `--continue`/`--abort` resume or restore after a conflict mid-apply.

If the user exits via cancel rather than apply, nothing changed — skip straight to
reporting that and stop. There is nothing to reconcile.

**A third outcome exists besides cancel and a clean apply: mid-apply, on a conflict.**
Applying (Ctrl+S) can hit a conflict partway through, in which case `gh stack modify`
exits neither cancelled nor fully applied — that's what the upstream-documented
`--continue`/`--abort` pair above is for. A conflicted apply is a rebase under the hood,
so it leaves the identical on-disk marker Step 2's precondition check already looks for.
Check for it before doing anything else, immediately after the TUI returns:

```bash
if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
  echo "gh stack modify exited mid-apply (conflict) — not cancelled, not fully applied."
  echo "Resolve the conflict, then run one of:"
  echo "  gh stack modify --continue   (after resolving and staging the conflict)"
  echo "  gh stack modify --abort      (to restore the pre-modify state instead)"
  echo "Re-run this check afterward; do not proceed to Step 5 until it passes clean."
  exit 1
fi
```

**Do not take Step 5's `after` snapshot while this check fails.** A snapshot taken
mid-apply reflects a transient, not-yet-settled state — the stack is still rebasing, not
a real "before" or "after." Reconciliation questions asked against it would look
legitimate but be built on incomplete information, and the answers **do** get written to
the manifest (Step 5), so this is worth stopping for rather than pressing ahead. Hand off
the `--continue`/`--abort` choice to the user exactly as printed above and wait; re-run
the same check once they report having done one of the two before moving to Step 5. An
`--abort` restores the pre-modify state, which is equivalent to the cancel case just
above — nothing to reconcile. A completed `--continue` is equivalent to a clean apply —
proceed to Step 5 normally.

### Step 5: Reconcile the manifest (multi-repo mode only)

Only reached once Step 4's mid-apply check has passed clean — never while
`.git/rebase-merge` or `.git/rebase-apply` is present.

Skip this step entirely in single-repo mode — there is no manifest.

```bash
after_json=$(gh stack view --json)
after=$(jq -r '.branches[].name' <<<"$after_json")
```

Compute the two set differences against the Step 3 snapshot:

```bash
dropped_or_renamed=$(comm -23 <(sort <<<"$before") <(sort <<<"$after"))
new_names=$(comm -13 <(sort <<<"$before") <(sort <<<"$after"))
```

- **If both are empty**, every branch from before is still present under the same name.
  This is either no change, or a **pure reorder**. Reordering needs **no manifest
  change** — the manifest's steps carry explicit numbers
  (`~/.claude/docs/stacked-pr-workflow.md#manifest-schema`), not positional order, so shuffling the
  local branch stack does not desynchronize anything the manifest records. Say this
  explicitly in the summary so it doesn't read as a missed case.
- **Otherwise, for each name in `$dropped_or_renamed`, ask the user**: was `<name>`
  dropped or folded away, or renamed? **Never guess a rename from position** — position is
  not a reliable key here, since the same TUI session can also reorder, so array position
  in `$after` no longer lines up with `$before`. If the answer is "dropped/folded", apply
  the drop snippet from `~/.claude/docs/stacked-pr-workflow.md#manifest-writes` with `$r` = this
  repo, `$b` = the branch name. If the answer is "renamed", ask which name in
  `$new_names` it became, then apply the rename snippet from the same section with `$r` =
  this repo, `$old`/`$new` = the confirmed pair, and remove that name from the
  `$new_names` pool so it isn't offered again for a different old name.
- **Any name still left in `$new_names`** after every `$dropped_or_renamed` entry has been
  resolved came from an insert, not a rename. This command does not guess a step number
  for it — report it and point the user at `/stack-commit` (or manual manifest editing) to
  give it one.

### Step 6: Remind about resubmitting

If any branch carries a `.pr` field in `$before_json` or `$after_json` (i.e. the stack, or
part of it, was ever submitted), and Step 4 did not end in cancel, print:

```
Structure changed — run /stack-create-pr to push and recreate the stack on GitHub.
```

## Rules

- Do NOT include `Co-Authored-By` lines.
- NEVER script or automate the `gh stack modify` TUI in any way — it is interactive by
  design, and this command's only job is to reconcile the manifest before and after it.
- NEVER fall back to hand-rolled branch surgery (`git rebase -i`, manual delete/rename) if
  `gh stack` is unavailable — stop instead (see Preflight).
- NEVER take Step 5's `after` snapshot while `.git/rebase-merge` or `.git/rebase-apply`
  exists — that means the TUI exited mid-apply on a conflict, not cancelled and not fully
  applied, and a snapshot taken then reflects a transient state, not a real "after." Hand
  off `gh stack modify --continue`/`--abort` and re-check before proceeding (Step 4).
- The manifest stores branches, never PR numbers
  (`~/.claude/docs/stacked-pr-workflow.md#manifest-schema`) — Step 6's resubmit check reads `.pr`
  from live `gh stack view --json` output, never from the manifest.
- Repo keys in the manifest are directory names relative to the workspace root.
- **Never infer a rename from position.** Always ask the user which old name maps to
  which new one (Step 5) — guessing from array position silently corrupts cross-repo
  correlation, and is especially unsafe here because the same TUI session can reorder in
  addition to renaming.
- **Reordering alone changes nothing in the manifest.** Steps carry explicit numbers, not
  positional order — say so plainly in the summary rather than leaving it implicit.
- Every claim about `gh stack modify`'s own behavior (its keybindings, what drop/fold
  preserve or discard, `--continue`/`--abort`) is upstream-documented from the
  github/gh-stack README, not locally verified — an interactive TUI cannot be driven from
  this environment. Say so; do not present it as measured.
- If the stack (or any part of it) was ever submitted, remind the user to run
  `/stack-create-pr` after a structural change (Step 6) — this command never pushes or
  resubmits anything itself.
