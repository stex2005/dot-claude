---
description: Create chained PRs for the entire step-branch stack, or retarget PRs after a merge.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Bash(ruff *), Read, Write, Edit, Glob
---

## Context

- Workspace: /home/stefano/repos/development_ws/src (NOT a git repo itself)
- Arguments: $ARGUMENTS (optional: repo name, or "retarget" to retarget after a merge)

**IMPORTANT:** The workspace contains multiple independent git repos as subdirectories under `src/`. You MUST `cd` into the correct repo before running any git commands.

## Your task

Create stacked PRs for all step branches in the stack, or retarget existing PRs after a merge.

### Step 0: Find the right repo

1. If the user provided a repo name argument, resolve it (same shorthands as `/commit-stack`).
2. If no argument, scan repos for step branches and ask which repo to operate on.

All subsequent commands MUST run inside the resolved repo directory.

### Step 1: Map the stack

1. Find all step branches: `git branch --list 'feature/stefano/refactor/step*'`
2. Sort by step number.
3. Determine the base branch (typically `develop`).
4. Build the chain: develop ← step1 ← step2 ← step3 ← ...
5. For each step branch, check if a PR already exists:
   ```bash
   gh pr list --head <branch-name> --json number,baseRefName,state,url
   ```

### Step 2: Create missing PRs (default mode)

For each step branch that does NOT have an open PR:

1. Determine the correct base:
   - step1 → `develop`
   - stepN → step(N-1) branch
2. Push the branch if not already pushed: `git push -u origin <branch>`
3. Read the plan file for this step to generate the PR description.
4. Generate a PR description following the repo's PULL_REQUEST_TEMPLATE if available. Otherwise:
   - **Overview**: What this step accomplishes (from the plan).
   - **Stack position**: "Step N of M — targets `<base-branch>`"
   - **Summary of Changes**: Bullet list of main changes.
   - **Testing**: How to test this step.
5. Write the description to `pr-description.md` for the user to review.
6. Wait for the user to confirm before creating each PR.
7. Create the PR: `gh pr create --base <base-branch> --head <step-branch> --title "<title>" --body-file pr-description.md`
8. Clean up `pr-description.md`.

### Step 3: Retarget mode (when argument is "retarget")

After a step merges into develop:

1. Find which step branches still have open PRs.
2. Identify the new bottom of the stack (the lowest step with an open PR).
3. Retarget it to `develop`:
   ```bash
   gh pr edit <PR_NUMBER> --base develop
   ```
4. Report what was retargeted.

### Step 4: Summary

Print:
```
## Stack PRs for <repo>

| Step | Branch | PR | Base | Status |
|------|--------|----|------|--------|
| 1    | step1-split-files | #386 | develop | merged |
| 2    | step2-gripper | #389 | develop (retargeted) | open |
| 3    | step3-planning | #390 | step2-gripper | open |
```

## Rules

- Do NOT include `Co-Authored-By` lines in PR descriptions.
- NEVER use destructive git commands.
- Run `ruff check --fix` and `ruff format` on changed Python files before pushing.
- Always let the user review and edit the PR description before submitting.
- Keep PR descriptions concise — the reviewer's time is limited.
- Each PR should be < 400 lines of diff. If a step is larger, warn the user and suggest splitting.
