---
description: Commit current changes to the correct step branch in the stack. If changes belong to the next step, create the next step branch automatically.
allowed-tools: Bash(git *), Bash(gh *), Bash(ruff *), Bash(ls *), Bash(cd *), Bash(for *), Read, Write, Edit, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: repo name in multi-repo mode)

## Workspace detection

Detect the workspace mode before proceeding:

1. **Single-repo mode**: The current directory contains a `.git` folder → operate on this repo directly. No need to `cd` anywhere.
2. **Multi-repo mode**: The current directory does NOT contain `.git`, but has subdirectories that do → `cd` into the correct sub-repo before running git commands.
3. **Error**: Neither condition is met → inform the user and stop.

## Your task

Commit the current uncommitted changes to the correct step branch in the stack. Determine where the changes belong conceptually, commit them there, and advance to the next step if appropriate.

### Step 0: Find the right repo(s)

**Single-repo mode:** Use the current directory. Skip repo resolution.

**Multi-repo mode:**
1. If the user provided a repo name argument, resolve it (try exact match first, then substring match against subdirectory names).
2. If no argument, scan all subdirs for repos with uncommitted changes:
   `for d in */; do (cd "$d" && git status --porcelain 2>/dev/null | grep -q . && echo "$d"); done`
3. If multiple repos have changes, process each one separately or ask the user.

All subsequent git commands MUST run inside the resolved repo directory.

### Step 1: Identify the current stack

1. Find all existing step branches: `git branch --list '*/step*'`
2. Determine which step the current branch is (e.g. `refactor/step3-gripper-command`, `feature/step3-add-api`).
3. Read the relevant plan from `~/.claude/plans/` to understand what each step covers.

### Step 2: Classify the changes

1. Look at the uncommitted diff (staged + unstaged).
2. Determine which step the changes belong to:
   - **Current step**: changes match the current step's scope in the plan.
   - **Next step**: changes are conceptually the next step in the plan (e.g. working on step3 branch but changes implement step4).
   - **Mixed**: some changes belong to current step, some to next. Flag this and ask user how to split.

### Step 3: Commit to the right place

**If changes belong to the current step:**
1. Run linting/formatting if configured for the project (e.g. `ruff check --fix && ruff format` for Python, or whatever the repo uses). Skip if no linter is configured.
2. Stage all relevant files.
3. Commit with a message following repo convention (`feat:`, `fix:`, `refactor:`, etc.).
4. Stay on the current branch.
5. **Update plan status**: mark this step as `in-progress` in the plan file.

**If changes belong to the next step:**
1. Determine the next step number and slug from the plan.
2. Run linting/formatting if configured for the project. Skip if no linter is configured.
3. Check if uncommitted changes on the current step need committing first. If so, ask.
4. **Update plan status**: mark the current step as `done` in the plan file.
5. Create the next step branch from the current one, using the same prefix as existing step branches:
   `git checkout -b <prefix>/step<N+1>-<slug>` (e.g. `refactor/step4-foo` if existing branches use `refactor/`)
6. Stage and commit the changes there.
7. **Update plan status**: mark the new step as `in-progress` in the plan file.
8. Report the new branch name.

**If changes are mixed:**
1. Present which files/hunks belong to which step.
2. Ask the user how to proceed:
   - Commit everything to current step
   - Split: commit current-step changes first, then create next branch for the rest
   - Let the user decide file by file

### Step 4: Update plan status

When updating plan files in `~/.claude/plans/`:
1. Find the plan file that corresponds to the current step.
2. Replace the `## Status` line content with the new status (`done`, `in-progress`, or `todo`).
3. If no matching plan file is found, skip this step silently.

### Step 5: Summary

Print:
```
Committed to: <branch-name>
Commit: <sha> <message>
Plan status: <step> → <new-status>
Next step branch: <created | already exists | not yet needed>
Current branch: <where you are now>
```

## Rules

- Do NOT include `Co-Authored-By` lines.
- NEVER use destructive git commands.
- Run linting/formatting if configured for the project before committing.
- If there's nothing to commit, say so and stop.
- When creating the next step branch, always branch from the current step (not from base).
- Use the plan file to determine step slugs and scope. If no plan matches, ask the user.
