---
description: Checkout the latest step branch across all repos in the workspace so you start clean.
allowed-tools: Bash(git *), Bash(ls *)
---

## Context

- Workspace: /home/stefano/repos/development_ws/src
- Repos: !`ls -d /home/stefano/repos/development_ws/src/*/`

## Your task

For each git repo in the workspace, find and checkout the highest-numbered `feature/stefano/refactor/step*` branch. If none exists, checkout `feature/stefano/refactor-base`. If neither exists, checkout `develop`.

### Steps

1. For each directory in the workspace that contains a `.git` folder:
   a. List branches matching `feature/stefano/refactor/step*`.
   b. Sort by step number and pick the highest.
   c. If no step branch exists, check if `feature/stefano/refactor-base` exists.
   d. If neither exists, fall back to `develop`.
   e. Checkout the selected branch.
2. Print a summary table:
   ```
   | Repo | Branch | Status |
   |------|--------|--------|
   ```
3. Verify all repos have a clean working tree. Flag any with uncommitted changes.

### Rules

- NEVER use destructive git commands.
- If a repo has uncommitted changes, warn the user and do NOT checkout. Skip that repo.
- Every repo gets checked out to something (step → refactor-base → develop).
