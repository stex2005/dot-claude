---
description: "Checkout a specific step branch across all repos. Argument: base, step0, step1, ..., or latest (default: latest)."
allowed-tools: Bash(git *), Bash(ls *)
---

## Context

- Workspace: /home/stefano/repos/development_ws/src
- Repos: !`ls -d /home/stefano/repos/development_ws/src/*/`
- Argument: $ARGUMENTS (one of: `base`, `step0`, `step1`, `step2`, ..., `latest`; defaults to `latest` if empty)

## Your task

For each git repo in the workspace, checkout the branch corresponding to the requested argument.

Branch names follow the pattern `refactor/stepN-<optional-slug>` (e.g. `refactor/step1`, `refactor/step2-gripper-class`). When the user says `stepN`, match any branch whose name starts with `refactor/stepN` (use the glob `refactor/stepN*`).

| Argument | Target branch |
|----------|---------------|
| `base` | `refactor/base` |
| `step0` | Branch matching `refactor/step0*` |
| `step1` | Branch matching `refactor/step1*` |
| `stepN` | Branch matching `refactor/stepN*` |
| `latest` | The highest-numbered `refactor/step*` branch. If none exists, fall back to `refactor/base`. If that doesn't exist either, fall back to `develop`. |

If the argument is empty or not provided, treat it as `latest`.

### Steps

1. Parse the argument. Determine the target branch pattern (or selection strategy for `latest`).
2. For each directory in the workspace that contains a `.git` folder:
   a. If the target is `base`, checkout `refactor/base`.
   b. If the target is `stepN`, list branches matching `refactor/stepN*`. If exactly one matches, checkout it. If multiple match, list them and ask the user which one. If none match, fall back to `latest` behavior for that repo.
   c. If the target is `latest`, list all branches matching `refactor/step*`, sort by step number, pick the highest. Fall back to `refactor/base`, then `develop`.
   d. If no matching branch exists in a repo (even after fallback), warn the user and skip that repo.
3. Print a summary table:
   ```
   | Repo | Branch | Status |
   |------|--------|--------|
   ```
4. Verify all repos have a clean working tree. Flag any with uncommitted changes.

### Rules

- NEVER use destructive git commands.
- If a repo has uncommitted changes, warn the user and do NOT checkout. Skip that repo.
- If a specifically requested step branch doesn't exist in a repo, fall back to `latest` behavior (highest step → `refactor/base` → `develop`).
