---
description: Show a per-repo dashboard of all step branches, current position, uncommitted changes, and plan status.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Read, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: repo name or plan name)
- Plans directory: ~/.claude/plans/

## Workspace detection

Detect the workspace mode before proceeding:

1. **Single-repo mode**: The current directory contains a `.git` folder → show status for this repo only.
2. **Multi-repo mode**: The current directory does NOT contain `.git`, but has subdirectories that do → show status for all sub-repos.
3. **Error**: Neither condition is met → inform the user and stop.

## Your task

Show a comprehensive status dashboard for the stacked branch workflow.

### Step 1: Discover repos and branches

**Single-repo mode:** Operate on the current directory as the only repo.

**Multi-repo mode:** List all subdirectories that contain a `.git` folder.

For each repo:
   a. Find all branches matching `*/step*`.
   b. Identify the current branch (`git branch --show-current`).
   c. Check for uncommitted changes (`git status --porcelain`).
   d. For each step branch, show the commit count ahead of the previous step (or the base branch for step1).

### Step 2: Check open PRs

For each repo with step branches, check for open PRs:
```bash
gh pr list --head <branch-name> --json number,title,baseRefName,state,url
```

### Step 3: Load plan status

1. If the user provided a plan name, look in `~/.claude/plans/<name>/`.
2. Otherwise, scan `~/.claude/plans/` for the most recently modified plan directory.
3. Read each plan file and extract the `## Status` field.

### Step 4: Print the dashboard

For each repo, print a table:

```
## <repo-name>  (on: <current-branch>)  [clean | X uncommitted files]

| Step | Branch | Commits | PR | Plan Status |
|------|--------|---------|----|-------------|
| 1    | step1-split-files | +3 ahead of develop | #386 → develop (open) | done |
| 2    | step2-gripper | +2 ahead of step1 | #389 → step1 (open) | in-progress |
| 3    | step3-planning | +0 (current) | — | todo |
```

If a repo has no step branches, skip it or note "no stack branches".

### Rules

- This is a **read-only** command. Do NOT modify anything.
- If `gh` is not authenticated or fails, skip the PR column and note the issue.
- Show repos alphabetically.
