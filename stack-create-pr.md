---
description: Create chained PRs for step branches — all steps or a single step across repos, with cross-references. Retarget after merges.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Bash(ruff *), Read, Write, Edit, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional — see modes below)

## Workspace detection

Detect the workspace mode before proceeding:

1. **Single-repo mode**: The current directory contains a `.git` folder → operate on this repo only. Skip multi-repo scanning.
2. **Multi-repo mode**: The current directory does NOT contain `.git`, but has subdirectories that do → scan sub-repos and `cd` into each before running git commands.
3. **Error**: Neither condition is met → inform the user and stop.

In multi-repo mode, resolve repo name arguments by exact match first, then substring match against subdirectory names.

## Modes

Parse the arguments to determine the mode:

| Argument | Mode | Behavior |
|----------|------|----------|
| (none) | **all** | Create PRs for all steps missing a PR. In single-repo mode, operate on this repo. In multi-repo mode, scan all sub-repos (ask which if ambiguous). |
| `<repo-name>` | **all (single repo)** | (Multi-repo only) Create PRs for all steps in that repo. |
| `step<N>` or `<N>` | **single step** | Create PRs for that step. In multi-repo mode, across all repos that have the branch. Cross-reference them. |
| `retarget` | **retarget** | Retarget PRs after a step merges. |

## Your task

### Step 0: Discover step branches

**Single-repo mode:**
1. Find step branches: `git branch --list '*/step*'`
2. Sort by step number.
3. Determine the base branch (detect from repo: `develop`, `main`, or `master`).
4. Build the chain: base ← step1 ← step2 ← step3 ← ...

**Multi-repo mode:**
1. Scan all sub-repos for step branches:
   ```bash
   for d in */; do (cd "$d" && branches=$(git branch --list '*/step*' 2>/dev/null); [ -n "$branches" ] && echo "REPO:${d%/}" && echo "$branches"); done
   ```
2. Sort branches by step number.
3. Determine the base branch per repo.
4. Build the chain per repo: base ← step1 ← step2 ← step3 ← ...
5. For each step branch, check if a PR already exists:
   ```bash
   gh pr list --head <branch-name> --json number,baseRefName,state,url
   ```

### Step 1: Determine scope

**All mode** (no step argument):
- **Single-repo mode:** Operate on the current repo.
- **Multi-repo mode:** If a repo name was given, operate on that repo only. If no argument, scan for repos with step branches. If multiple repos have them, ask the user which repo to operate on (or offer "all repos").
- Target: all step branches missing a PR in the selected repo(s).

**Single step mode** (step number given):
- Find all repos that have a branch matching that step number.
- Report which repos need PRs and which already have them. If all already have PRs, say so and stop.
- Target: that one step across all matching repos.

**Retarget mode** (`retarget` argument):
- Jump to the Retarget section below.

### Step 2: Prepare

For each repo+branch that needs a PR:

1. `cd` into the repo.
2. Determine the correct base:
   - step1 → the repo's default branch (`develop`, `main`, or `master`)
   - stepN → step(N-1) branch if it exists, otherwise the default branch
3. Run linting/formatting if configured for the project (e.g. `ruff` for Python). Skip if no linter is configured.
4. Push the branch if not already pushed: `git push -u origin <branch>`

### Step 3: Draft PR descriptions

1. Read the plan file for the step from `~/.claude/plans/` to understand the scope.
2. For each repo, generate a PR description following the repo's PULL_REQUEST_TEMPLATE if available. Otherwise:
   - **Overview**: What this step accomplishes (from the plan), scoped to this repo's changes.
   - **Stack position**: "Step N of M — targets `<base-branch>`"
   - **Summary of Changes**: Bullet list of main changes.
   - **Testing**: How to test this step.
   - If **single step mode** and multiple repos: add a **Cross-repo PRs** placeholder.
3. Write the description to `pr-description.md` in the repo root.
4. Present all descriptions to the user for review. Wait for confirmation before proceeding.

### Step 4: Create PRs

For each repo (in order):

1. Create the PR:
   ```bash
   gh pr create --base <base-branch> --head <step-branch> --title "<title>" --body-file pr-description.md
   ```
2. Capture the PR URL and number.
3. Clean up `pr-description.md`.

### Step 5: Cross-reference (single step mode only)

When a single step spans multiple repos, do a second pass to add cross-references:

Update each PR body to include:

```markdown
## Cross-repo PRs

This change spans multiple repositories:

| Repo | PR |
|------|----|
| **this repo** | **#<number>** |
| other_repo | org/other_repo#<number> |
```

Use `gh pr edit <number> --body <updated-body>` to update each PR.
Use `org/repo#number` format so GitHub auto-links across repos. Determine the org from the remote URL.

### Retarget mode

After a step merges into develop:

1. Find which step branches still have open PRs.
2. Identify the new bottom of the stack (the lowest step with an open PR).
3. Retarget it to `develop`:
   ```bash
   gh pr edit <PR_NUMBER> --base develop
   ```
4. Report what was retargeted.

### Summary

Print a table appropriate to the mode:

```
| Repo | Step | Branch | PR | Base | Status |
|------|------|--------|----|------|--------|
| common | 2 | step2-gripper | #142 | develop | created |
| hal    | 2 | step2-gripper | #87  | step1-split | created |
| sim    | 2 | step2-gripper | #203 | develop | already existed |
```

## Rules

- Do NOT include `Co-Authored-By` lines in PR descriptions.
- NEVER use destructive git commands.
- Run linting/formatting if configured for the project before pushing.
- Always let the user review and edit the PR description before submitting.
- Keep PR descriptions concise — the reviewer's time is limited.
- Each PR should be < 400 lines of diff. If larger, warn the user and suggest splitting.
- Use `org/repo#number` format for cross-references so GitHub renders them as clickable links.
