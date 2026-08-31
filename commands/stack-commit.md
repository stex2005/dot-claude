---
description: Commit current changes to the correct step branch in the stack. If changes belong to the next step, create the next step branch automatically.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ruff *), Bash(ls *), Bash(cd *), Bash(for *), Read, Write, Edit, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: repo name in multi-repo mode; optional: commit message)

## Preflight

Run the guard block from `docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack` is the only supported mechanism for creating stack branches — **never**
fall back to hand-rolled `git checkout -b` stacking, even if the guard fails. A silent
fallback would create branches the manifest does not know about.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is written
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

### Step 1: Identify the current stack

1. Find the current branch and, in multi-repo mode with a manifest present, the highest
   recorded step number via the manifest-read snippet in
   `docs/stacked-pr-workflow.md#manifest-reads`.
2. Determine which step the current branch represents. `gh stack view --json` describes
   the stack of branches in this repo; the manifest (multi-repo mode) correlates that
   branch back to a step number and title across repos.
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

1. Determine the next step number from the highest step recorded so far (manifest, or
   `gh stack view --json` in single-repo mode) + 1, and its title from the plan (or from
   the user, if no plan is available).
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

This is expected behavior, not an error. In this case the branch being committed to is
still step 1: record it as step 1 in the manifest and mark step 1 `in-progress` (not
`done`, since there is no earlier step to close out), not as a new step.

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
`docs/stacked-pr-workflow.md#manifest-writes`, with `$r` = the current repo's directory
name, `$n` = the step number from Step 2/3 (the current step's number for the
existing-step path, or the new step number for the new-step and no-prior-commits paths),
and `$t` = the step title from the plan (or from the user).

The manifest stores branches only, never PR numbers.

### Step 5: Update plan status

1. Resolve the plan file to update:
   - Multi-repo mode: use `.plan` from the manifest, already resolved in Step 1. If it is
     the empty string `""` (a stack started from a bare name, per the Task 2 ruling in
     Step 1), there is no plan file — **skip this step silently**.
   - Single-repo mode: use the plan file resolved via `~/.claude/plans/` in Step 1.
   - If Step 1 found no matching plan file, **skip this step silently**, same as the `""`
     case above.
2. Within that plan file, locate the section for the step being updated. Key this off the
   step's **number and title** (from Step 2/3 and the manifest), not off the branch name —
   branch names no longer encode the step, since `gh stack` auto-names them.
3. Replace that step's `## Status` line content with the new status (`done`,
   `in-progress`, or `todo`), per Step 3's rules:
   - Existing-step path: mark the current step `in-progress`.
   - New-step path: mark the previous step `done`, then the new step `in-progress`.
   - No-prior-commits path: mark step 1 `in-progress` (there is no earlier step to close).

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
- Use the plan to determine step titles and scope. If no plan is available (`.plan == ""`, or single-repo mode with no matching plan file), ask the user.
