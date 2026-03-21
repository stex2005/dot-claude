---
description: "Checkout a specific step branch across all repos. Argument: base, step0, step1, ..., or latest (default: latest)."
allowed-tools: Bash(git *), Bash(ls *)
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Argument: $ARGUMENTS (one of: `base`, `step0`, `step1`, `step2`, ..., `latest`; defaults to `latest` if empty)

## Workspace detection

Detect the workspace mode before proceeding:

1. **Single-repo mode**: The current directory contains a `.git` folder → operate on this repo only.
2. **Multi-repo mode**: The current directory does NOT contain `.git`, but has subdirectories that do → operate on all sub-repos.
3. **Error**: Neither condition is met → inform the user and stop.

## Your task

For each git repo in the workspace, checkout the branch corresponding to the requested argument.

Branch names follow the pattern `*/stepN-<optional-slug>` (e.g. `refactor/step1`, `feature/step2-gripper-class`). When the user says `stepN`, match any branch whose name contains `/stepN` (use the glob `*/stepN*`).

| Argument | Target branch |
|----------|---------------|
| `base` | Branch matching `*/base` (e.g. `refactor/base`, `feature/base`) |
| `step0` | Branch matching `*/step0*` |
| `step1` | Branch matching `*/step1*` |
| `stepN` | Branch matching `*/stepN*` |
| `latest` | The highest-numbered `*/step*` branch. If none exists, fall back to `*/base`. If that doesn't exist either, fall back to the repo's default branch (`develop`, `main`, or `master`). |

If the argument is empty or not provided, treat it as `latest`.

### Steps

1. Parse the argument. Determine the target branch pattern (or selection strategy for `latest`).
2. For each repo (single repo in single-repo mode, or each subdirectory with `.git` in multi-repo mode):
   a. If the target is `base`, checkout `refactor/base`.
   b. If the target is `stepN`, list branches matching `*/stepN*`. If exactly one matches, checkout it. If multiple match, list them and ask the user which one. If none match, fall back to `latest` behavior for that repo.
   c. If the target is `latest`, list all branches matching `*/step*`, sort by step number, pick the highest. Fall back to `*/base`, then the repo's default branch.
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
