---
description: Create PRs for a single step branch across all repos that have it, with cross-references between them.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Bash(ruff *), Read, Write, Edit, Glob
---

## Context

- Workspace: /home/stefano/repos/development_ws/src (NOT a git repo itself)
- Arguments: $ARGUMENTS (optional: step number or branch name, e.g. "step2" or "refactor/step2-gripper")
- Repo shorthands: `task_executor` → `unloading_robot_task_executor`, `common` → `unloading_robot_common`, `hal` → `unloading_robot_hal`, `sim` → `unloading_robot_sim`, `orchestrator` → `unloading_robot_process_orchestrator`

**IMPORTANT:** The workspace contains multiple independent git repos as subdirectories under `src/`. You MUST `cd` into the correct repo before running any git commands.

## Your task

Create a PR for a single step branch across every repo that has that branch, and cross-reference the PRs in their descriptions.

### Step 0: Identify the step and repos

1. If the user provided a step number or branch name, resolve it:
   - `step2` or `2` → find branches matching `refactor/step2*`
   - `refactor/step2-gripper` → use exactly
2. If no argument, scan all repos for step branches and show a summary. Ask which step to create PRs for.
3. Find all repos that have the target step branch:
   ```bash
   for d in */; do (cd "$d" && git branch --list 'refactor/step<N>*' 2>/dev/null | grep -q . && echo "$d"); done
   ```
4. For each matching repo, check if a PR already exists:
   ```bash
   gh pr list --head <branch-name> --json number,baseRefName,state,url
   ```
5. Report which repos need PRs and which already have them. If all repos already have PRs, say so and stop.

### Step 1: Prepare each repo

For each repo that needs a PR:

1. `cd` into the repo.
2. Determine the correct base branch:
   - If step1 → `develop`
   - If stepN and step(N-1) branch exists → step(N-1) branch
   - Otherwise → `develop`
3. Run `ruff check --fix` and `ruff format` on changed Python files.
4. Push the branch if not already pushed: `git push -u origin <branch>`

### Step 2: Draft PR descriptions

1. Read the plan file for this step from `~/.claude/plans/` to understand the scope.
2. For each repo, generate a PR description following the repo's PULL_REQUEST_TEMPLATE if available. Otherwise use:
   - **Overview**: What this step accomplishes (from the plan), scoped to this repo's changes.
   - **Summary of Changes**: Bullet list of main changes in this repo.
   - **Testing**: How to test this repo's changes.
   - **Cross-repo PRs**: Leave a placeholder — this section will be filled in Step 3.
3. Write each description to `pr-description.md` inside the repo root.
4. Present all descriptions to the user for review. Wait for confirmation before proceeding.

### Step 3: Create PRs and cross-reference

This must happen in two passes:

**Pass 1 — Create all PRs:**

For each repo (in order):

1. Create the PR:
   ```bash
   gh pr create --base <base-branch> --head <step-branch> --title "<step-slug>: <repo-specific summary>" --body-file pr-description.md
   ```
2. Capture the PR URL and number.
3. Clean up `pr-description.md`.

**Pass 2 — Add cross-references:**

Now that all PR URLs are known, update each PR body to include the **Cross-repo PRs** section:

```markdown
## Cross-repo PRs

This change spans multiple repositories:

| Repo | PR |
|------|----|
| **this repo** | **#<number>** |
| other_repo | org/other_repo#<number> |
| ...  | ... |
```

Use `gh pr edit <number> --body <updated-body>` to update each PR.

To build the cross-reference links, use the format `org/repo#number` so GitHub auto-links them across repos. Determine the org from the remote URL.

### Step 4: Summary

Print:

```
## Cross-repo PRs for <step-branch>

| Repo | Branch | PR | Base | Status |
|------|--------|----|------|--------|
| unloading_robot_common | refactor/step2-gripper | #142 | develop | created |
| unloading_robot_hal | refactor/step2-gripper | #87 | step1-split | created |
| unloading_robot_sim | refactor/step2-gripper | #203 | develop | already existed |
```

## Rules

- Do NOT include `Co-Authored-By` lines in PR descriptions.
- NEVER use destructive git commands.
- Run `ruff check --fix` and `ruff format` on changed Python files before pushing.
- Always let the user review and edit PR descriptions before submitting.
- Keep PR descriptions concise — the reviewer's time is limited.
- Each PR should be < 400 lines of diff. If a repo's diff is larger, warn the user and suggest splitting.
- Use `org/repo#number` format for cross-references so GitHub renders them as clickable links.
