---
description: Update an existing stack summary with the latest changes, status, and features.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Read, Write, Edit, Glob, Grep
---

## Context

- Workspace: /home/stefano/repos/development_ws/src (NOT a git repo itself)
- Arguments: $ARGUMENTS (optional: path to existing summary file)
- Repo shorthands: `task_executor` → `unloading_robot_task_executor`, `common` → `unloading_robot_common`, `hal` → `unloading_robot_hal`, `sim` → `unloading_robot_sim`, `orchestrator` → `unloading_robot_process_orchestrator`

**IMPORTANT:** The workspace contains multiple independent git repos as subdirectories under `src/`. You MUST `cd` into the correct repo before running any git commands.

## Your task

Update an existing stack summary file with the latest state of the step branches.

### Step 0: Find the existing summary

1. If the user provided a file path argument, use it.
2. Otherwise, look for `docs/stack-summary.md` in the workspace.
3. If no summary file is found, tell the user and suggest running `/stack-create-summary` first.
4. Read the existing summary file.

### Step 1: Gather current data

1. Scan all repos for step branches using `*/step*`:
   ```bash
   for d in */; do (cd "$d" && branches=$(git branch --list '*/step*' 2>/dev/null); [ -n "$branches" ] && echo "REPO:${d%/}" && echo "$branches"); done
   ```
2. For each repo with step branches, collect per step:
   - Branch name
   - Commit messages — compare against the correct parent:
     - step1: `git log --oneline develop..step1`
     - stepN: `git log --oneline step(N-1)..stepN`
   - Read the changed files to understand what was done
   - PR status: `gh pr list --head <branch> --json number,state,url`
3. Read the plan files from `~/.claude/plans/` to get step goals and status.

### Step 2: Compare and update

For each step in the existing summary:

1. **Status**: Update to reflect current PR state and plan status.
2. **Repos and changes**: Update summaries if new commits were added since the summary was written. Add new repos if a step now spans additional repos.
3. **Features implemented**: Add any new features that were implemented since the last summary. Do not remove existing features unless they were reverted.
4. **Goal**: Update only if the plan file changed.

For new steps not in the existing summary:
- Add them following the same template as `/stack-create-summary`.

For steps in the summary that no longer have branches (fully merged and cleaned up):
- Keep them in the summary but mark status as "merged and cleaned up".

### Step 3: Output

1. Update the summary file in place using the Edit tool.
2. Print the full updated summary to the console so the user can copy-paste it into Confluence.
3. Call out what changed: which steps were updated, which are new, which were completed.

## Rules

- Preserve the existing structure and wording where nothing changed — don't rewrite sections unnecessarily.
- Keep summaries concise — this is an overview, not a changelog.
- Use short repo names (strip `unloading_robot_` prefix) for readability.
- Compare each step against its parent branch (step(N-1)), not against develop, to show only that step's changes.
