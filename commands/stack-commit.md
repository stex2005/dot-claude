---
description: Commit current changes to the correct step branch in the stack. If changes belong to the next step, create the next step branch automatically.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ruff *), Bash(ls *), Bash(cd *), Bash(for *), Bash(mv *), Read, Write, Edit, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: repo name in multi-repo mode; optional: commit message)

## Preflight

Run the guard block from `~/.claude/docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack` is the only supported mechanism for creating stack branches — **never**
fall back to hand-rolled `git checkout -b` stacking, even if the guard fails. A silent
fallback would create branches the manifest does not know about.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`~/.claude/docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is written
only when `MODE=multi`; in single-repo mode `gh stack`'s own `.git/gh-stack` state
suffices and Step 4 below is skipped entirely.

## Your task

Commit the current uncommitted changes to the correct step branch in the stack. Determine
where the changes belong conceptually, commit them there via `gh stack`, and advance to
the next step if appropriate.

### Step 0: Find the right repo(s)

**Single-repo mode:** Use the current directory. Skip repo resolution.

**Multi-repo mode:**
1. If the user provided a repo name argument, resolve it (try exact match first, then substring match against subdirectory names).
2. If no argument, scan all subdirs for repos with uncommitted changes:
   `for d in */; do (cd "$d" && git status --porcelain 2>/dev/null | grep -q . && echo "$d"); done`
3. If multiple repos have changes, process each one separately or ask the user.

All subsequent git and `gh stack` commands MUST run inside the resolved repo directory.

**Then check each resolved repo actually has a stack, before doing anything else.** "Has
uncommitted changes" is a different question, and Step 3's `gh stack add` fails opaquely
in a repo that was never initialized — *after* Step 3's linting has already rewritten
files:

```bash
gh stack view --json >/dev/null 2>&1; rc=$?
```

- `rc == 2` — **no stack in this repo.** Nothing in this workflow adds a repo to an
  existing stack after the fact (no command writes a new key into the manifest's
  `trunk`), so do not improvise one. Report
  `<repo>: no stack here — re-run /stack-start including this repo, then re-run
  /stack-commit`, drop the repo from this run, and continue with the others. Never run
  `gh stack init` or `gh stack add` to paper over it.
- `rc == 6` — the repo's current branch belongs to several stacks. Report
  `<repo>: on <branch>, which belongs to multiple stacks — check out a non-trunk branch
  of the intended stack and re-run`, drop the repo, and continue.
- Any other non-zero exit is a real failure — report it and stop
  (`~/.claude/docs/stacked-pr-workflow.md#exit-codes`).

**Single-repo mode:** run the same check on the current repo; `rc == 2` or `rc == 6` stops
the command with the same message, since there is no other repo to continue with.

### Step 1: Identify the current stack

1. Find the current branch and determine the highest step number recorded so far:
   - Multi-repo mode: read it from the manifest via the manifest-read snippet in
     `~/.claude/docs/stacked-pr-workflow.md#manifest-reads`.
   - Single-repo mode (no manifest exists — see "Workspace and manifest resolution"
     above): there is no branch-name pattern to parse under `gh stack` auto-naming
     (`MM-DD-<slug>`), so derive step numbers positionally instead. Run
     `gh stack view --json` and take `.branches`, which is ordered **bottom-first**
     (confirmed: index 0 is the branch closest to trunk). The step number for a branch
     is its **1-indexed position** in that array; the highest step number is the array's
     length. This is the single source of step numbers for single-repo mode — every
     other step in this command that needs a single-repo step number (Step 3's new-step
     path, Step 5) uses this same rule, not a separate derivation.
2. Determine which step the current branch represents:
   - Multi-repo mode: the manifest correlates the branch back to a step number and title
     across repos (manifest reads, as above).
   - Single-repo mode: find `.currentBranch` in the same `gh stack view --json` output,
     locate it in `.branches`, and its 1-indexed position is its step number, per the
     rule above. There is no step title source in single-repo mode beyond the plan
     itself (see below).
   - **`.currentBranch` is not always in `.branches`.** Measured: with trunk checked out,
     `gh stack view --json` reports `"currentBranch": "main"` while `.branches` holds only
     the layer branches (`~/.claude/docs/gh-stack-json-reference.md`), and `gh stack sync
     --prune` lands you there routinely by moving your checkout off a pruned branch. When
     the lookup finds no match there is **no current step** — do not fall back to the top
     of the stack and do not guess a number. Say so and stop:
     ```
     You are on <branch>, which is not part of this stack (its branches are: <list>).
     Check out the step branch these changes belong to — or, if they start a new step,
     the top of the stack (gh stack top) — and re-run.
     ```
     The same rule applies in multi-repo mode when the manifest correlates the current
     branch to no step: report and stop rather than inventing a step number, because that
     number is written straight into the manifest by Step 4.
3. Read the relevant plan to understand what each step covers:
   - Multi-repo mode: read `.plan` from the manifest. If it is the empty string `""` (a
     stack started from a bare name, per `/stack-start`), there is no plan file — fall
     back to asking the user which step the changes belong to instead of trying to
     classify against a plan that doesn't exist.
   - Single-repo mode, or no plan recorded: fall back to `~/.claude/plans/` if a
     matching plan file can be found there; otherwise ask the user.

### Step 2: Classify the changes

1. Look at the uncommitted diff (staged + unstaged).
2. Determine which step the changes belong to:
   - **Current step**: changes match the current step's scope in the plan.
   - **Next step**: changes are conceptually the next step in the plan (e.g. working on
     the current step's branch but changes implement the step after it).
   - **Mixed**: some changes belong to current step, some to next. Flag this and ask user
     how to split.

This classification is the judgment call this command exists to make — reading the plan
(or asking, when there is none) and deciding whether the diff extends the current layer
or starts a new one. Nothing below changes that judgment; it only changes how the result
is committed and recorded.

### Step 3: Commit to the right place

**If changes belong to the current step (existing step):**

Use a plain commit — **never** `gh stack add` for an existing step, since `gh stack add`
always creates a new layer and would produce a spurious branch on top of the correct one.

1. Run linting/formatting if configured for the project (e.g. `ruff check --fix && ruff
   format` for Python, or whatever the repo uses). Skip if no linter is configured.
2. Stage all relevant files.
3. Commit:
   ```bash
   git add -A && git commit -m "$message"
   ```
4. Stay on the current branch. The step number and title are unchanged from Step 1.
5. **Update plan status**: mark this step as `in-progress` in the plan file (mechanics in
   Step 5).

**If changes belong to the next step (new step):**

Let `gh stack` name and create the branch — **never** pass an explicit branch name to
`gh stack add`; branch names always come from its own `MM-DD-<slug>` auto-naming.

1. Determine the next step number as the highest step recorded so far + 1, using the
   source from Step 1 (manifest in multi-repo mode; the 1-indexed bottom-first position
   in `gh stack view --json .branches` in single-repo mode). Get its title from the plan
   (or from the user, if no plan is available).
2. Run linting/formatting if configured for the project. Skip if no linter is configured.
3. Check if uncommitted changes on the current step need committing first. If so, ask.
4. **Update plan status**: mark the current step as `done` in the plan file (mechanics in
   Step 5).
5. Create the new layer and commit there:
   ```bash
   gh stack add -Am "$message"
   ```
   This stages everything, creates a new layer on top of the current branch, and commits
   there in one step.
6. **Update plan status**: mark the new step as `in-progress` in the plan file (mechanics
   in Step 5).
7. Report the new branch name (Step 6).

**Expected warning immediately after `/stack-start`:** if the current branch has no
prior commits yet (true right after `gh stack init`, before any `/stack-commit` has run),
`gh stack add -Am` does **not** create a new layer — it commits to that branch instead,
printing:

```
⚠ Branch <x> has no prior commits — adding your commit here instead of creating a new branch
```

This is expected behavior, not an error. It changes only *where* the commit lands — on the
existing commitless branch rather than on a new layer above it. It does **not** change
which step the changes were classified as. **Record the branch under the step number Step
2 classified, exactly as Step 4 says**, and mark that step `in-progress` (there is no
earlier step for this branch to close out, since the branch had no commits).

Step 1 is merely the common case here, not the rule. `/stack-start` runs `gh stack init`
in **every** confirmed repo, so every repo starts with a commitless seed branch. If step
1 touches only repo A, then when repo B first contributes at step 2 its `gh stack add -Am`
hits this same no-prior-commits path — and hard-coding "step 1" there would record repo
B's branch under step 1. The manifest would then claim repo B is in step 1 and not step
2, so `/stack-checkout step2`, `/stack-create-pr step2` and `/stack-merge step2` would all
silently skip it.

**If changes are mixed:**
1. Present which files/hunks belong to which step.
2. Ask the user how to proceed:
   - Commit everything to current step (plain commit, per the existing-step path above)
   - Split: commit current-step changes first (plain commit), then run `gh stack add -Am`
     for the rest (new-step path above)
   - Let the user decide file by file

### Step 4: Read back the branch and record it in the manifest

Skip this step in single-repo mode.

```bash
branch=$(gh stack view --json | jq -r '.currentBranch')
```

Record `$branch` against the classified step using the record-a-branch snippet in
`~/.claude/docs/stacked-pr-workflow.md#manifest-writes`, with `$r` = the current repo's directory
name, `$n` = the step number from Step 2/3 (the current step's number for the
existing-step path, or the new step number for the new-step and no-prior-commits paths —
the no-prior-commits path never substitutes `1` for the classified number),
and `$t` = the step title from the plan (or from the user).

The manifest stores branches only, never PR numbers.

### Step 5: Update plan status

1. Resolve the plan file to update:
   - Multi-repo mode: use `.plan` from the manifest, already resolved in Step 1. If it is
     the empty string `""` (a stack started from a bare name — see Step 1.3), there is no
     plan file — **skip this step silently**.
   - Single-repo mode: use the plan file resolved via `~/.claude/plans/` in Step 1.
   - If Step 1 found no matching plan file, **skip this step silently**, same as the `""`
     case above.
2. Within that plan file, locate the section for the step being updated. Key this off the
   step's **number and title** from Step 2/3 — not off the branch name, since `gh stack`
   auto-names branches and they no longer encode the step. The step number's source is
   the manifest in multi-repo mode, or the 1-indexed bottom-first position in
   `gh stack view --json .branches` in single-repo mode, per Step 1.
3. Replace that step's `## Status` line content with the new status (`done`,
   `in-progress`, or `todo`), per Step 3's rules:
   - Existing-step path: mark the current step `in-progress`.
   - New-step path: mark the previous step `done`, then the new step `in-progress`.
   - No-prior-commits path: mark the **classified** step `in-progress` — the step number
     from Step 2/3, never a hard-coded step 1. (There is no earlier step to close, because
     the branch had no commits; that is the only thing this path changes.)

### Step 6: Summary

Print:
```
Committed to: <branch-name>
Commit: <sha> <message>
Step: <n> <title> (<existing | new>)
Manifest: <updated <repo> → step <n> | not applicable (single-repo mode)>
Plan status: <step> → <new-status>
Current branch: <where you are now>
```

## Rules

- Do NOT include `Co-Authored-By` lines.
- NEVER use destructive git commands.
- NEVER fall back to hand-rolled `git checkout -b` stacking if `gh stack` is unavailable — stop instead (see Preflight).
- NEVER pass an explicit branch name to `gh stack add`.
- NEVER use `gh stack add` for an existing step.
- Run linting/formatting if configured for the project before committing.
- If there's nothing to commit, say so and stop.
- NEVER run `gh stack add` (or `gh stack init`) in a repo with no stack — `rc == 2` from
  `gh stack view --json` means the repo was never included in `/stack-start`, and no
  command in this workflow adds a repo to an existing stack. Report it and tell the user
  to re-run `/stack-start` for that repo (Step 0).
- NEVER record a branch under a hard-coded step 1. The no-prior-commits warning changes
  where the commit lands, never which step it belongs to — always record under the step
  Step 2 classified.
- NEVER guess a step number when `.currentBranch` is not one of the stack's branches
  (trunk checked out, or a branch outside the stack) — report it and stop, because that
  guess is written into the manifest.
- Use the plan to determine step titles and scope. If no plan is available (`.plan == ""`, or single-repo mode with no matching plan file), ask the user.
