---
description: Commit current changes to the correct step branch in the stack. If changes belong to the next step, create the next step branch automatically.
allowed-tools: Bash(git *), Bash(gh *), Bash(ruff *), Bash(ls *), Bash(cd *), Bash(for *), Read, Write, Edit, Glob
---

## Context

- Working directory: /home/stefano/repos/development_ws/src (NOT a git repo itself)
- Arguments: $ARGUMENTS (optional: repo name, e.g. "task_executor" or "unloading_robot_task_executor")

**IMPORTANT:** The workspace contains multiple independent git repos as subdirectories under `src/`. You MUST `cd` into the correct repo before running any git commands. If the user provides a repo name argument, use it. Otherwise, detect which repos have uncommitted changes.

## Your task

Commit the current uncommitted changes to the correct step branch in the stack. Determine where the changes belong conceptually, commit them there, and advance to the next step if appropriate.

### Step 0: Find the right repo(s)

1. If the user provided a repo name argument, resolve it:
   - Exact match: `unloading_robot_task_executor`
   - Shorthand: `task_executor` → `unloading_robot_task_executor`, `common` → `unloading_robot_common`, `hal` → `unloading_robot_hal`, `sim` → `unloading_robot_sim`, `orchestrator` → `unloading_robot_process_orchestrator`
2. If no argument, scan all subdirs for repos with uncommitted changes:
   `for d in */; do (cd "$d" && git status --porcelain 2>/dev/null | grep -q . && echo "$d"); done`
3. If multiple repos have changes, process each one separately or ask the user.

All subsequent git commands MUST run inside the resolved repo directory (use `cd /home/stefano/repos/development_ws/src/<repo> && git ...`).

### Step 1: Identify the current stack

1. Find all existing step branches: `git branch --list 'refactor/step*'`
2. Determine which step the current branch is (e.g. `step3-gripper-command`).
3. Read the relevant plan from `~/.claude/plans/` to understand what each step covers.

### Step 2: Classify the changes

1. Look at the uncommitted diff (staged + unstaged).
2. Determine which step the changes belong to:
   - **Current step**: changes match the current step's scope in the plan.
   - **Next step**: changes are conceptually the next step in the plan (e.g. working on step3 branch but changes implement step4).
   - **Mixed**: some changes belong to current step, some to next. Flag this and ask user how to split.

### Step 3: Commit to the right place

**If changes belong to the current step:**
1. Run `ruff check --fix` and `ruff format` on changed Python files.
2. Stage all relevant files.
3. Commit with a message following repo convention (`feat:`, `fix:`, `refactor:`, etc.).
4. Stay on the current branch.
5. **Update plan status**: mark this step as `in-progress` in the plan file.

**If changes belong to the next step:**
1. Determine the next step number and slug from the plan.
2. Run `ruff check --fix` and `ruff format` on changed Python files.
3. Check if uncommitted changes on the current step need committing first. If so, ask.
4. **Update plan status**: mark the current step as `done` in the plan file.
5. Create the next step branch from the current one:
   `git checkout -b refactor/step<N+1>-<slug>`
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
- Run `ruff check --fix` and `ruff format` on changed Python files before committing.
- If there's nothing to commit, say so and stop.
- When creating the next step branch, always branch from the current step (not from base).
- Use the plan file to determine step slugs and scope. If no plan matches, ask the user.
