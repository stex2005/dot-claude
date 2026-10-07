---
description: Lint, format, and create a pull request for the current branch.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Bash(pwd *), Bash(ruff *), Bash(npm *), Bash(npx *), Bash(cargo *), Bash(find *), Read, Write, Edit, Glob
argument-hint: [base-branch]
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional — base branch override)

## Workspace detection

Detect the workspace mode before proceeding:

1. **Single-repo mode**: The current directory contains a `.git` folder → operate on this repo only.
2. **Multi-repo mode**: The current directory does NOT contain `.git`, but has subdirectories that do → scan sub-repos for the current branch and cross-reference PRs.
3. **Error**: Neither condition is met → inform the user and stop.

In multi-repo mode, use the user's current repo as the "primary" (ask which repo they intend to target if ambiguous — typically the repo they last `cd`'d into). Discover the current branch from the primary repo, then check every other sub-repo for a branch of the same name.

## Your task

Lint, format, and create a pull request for the current branch. If the same branch exists in multiple sibling repos (multi-repo mode), create chained PRs with a cross-repo reference table.

### Step 0: Find the git repo(s)

- **Single-repo mode:** the working directory is the repo. All subsequent commands run from the repo root.
- **Multi-repo mode:** ask the user which repo is primary if unclear. Then scan all sub-repos:
  ```bash
  for d in */; do (cd "$d" && branch=$(git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "REPO:${d%/} BRANCH:$branch"); done
  ```
  Collect the set of repos whose current branch matches the primary's current branch. Those are the "participating repos".

### Step 1: Identify current and base branches

For each participating repo:

- **Current branch:** `git branch --show-current`. If on `main`, `master`, or `develop`, warn the user and stop — PRs should be created from feature branches.
- **Base branch:** use `$ARGUMENTS` if provided. Otherwise, detect the default branch via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, falling back to whichever of `main`, `master`, or `develop` exists locally.

In multi-repo mode, the base branch may differ per repo — detect per-repo.

### Step 2: Check for existing PRs

For each participating repo, run:

```bash
gh pr list --head <current-branch> --json number,url,state,baseRefName
```

- If an open PR already exists, show it and ask whether to update its body (to refresh the cross-repo table) instead of creating a new one.
- If all repos already have PRs and the user declines to update, stop.

### Step 3: Lint and format changed files

For each participating repo:

- Detect the project's configured linter/formatter from project files: `pyproject.toml` → ruff/black, `package.json` → eslint/prettier, `Cargo.toml` → cargo fmt, `.clang-format` → clang-format. Skip if nothing is configured.
- Identify changed files vs the base branch: `git diff --name-only <base-branch>...HEAD` plus any unstaged/staged changes.
- Run the linter/formatter on the changed files only.
- If the tool reports unfixable errors, show them and ask how to proceed.
- If linting/formatting produced changes, stage and commit them with message `style: lint and format`.

### Step 4: Ensure branches are pushed

For each participating repo: `git push -u origin <current-branch>`. If a push fails, show the error and ask how to proceed.

### Step 5: Gather context for the PR description(s)

For each participating repo:

- `git log --oneline <base-branch>..HEAD` to see all commits on this branch.
- `git diff <base-branch>...HEAD --stat` to see scope.
- If the diff is > 400 lines, warn the user and suggest splitting.

### Step 6: Draft PR description(s)

For each participating repo:

1. Check for a pull request template (`.github/PULL_REQUEST_TEMPLATE.md` or `.github/pull_request_template.md`). If present, use it as the structure.
2. Otherwise, draft with:
   - **Summary**: 1-3 bullet points — what this PR does and why (scoped to this repo's changes in multi-repo mode).
   - **Changes**: brief list of key changes.
   - **Test plan**: how to verify.
3. **Cross-repo PRs** (only in multi-repo mode when ≥2 repos participate): Append the table below at the **very bottom** of the PR body — after the template/summary/changes/test-plan, never in the middle. This keeps the reviewer-facing summary above the fold and the cross-links as a footer.

   Use `org/repo#number` format so GitHub auto-links. Determine the org from each repo's remote URL (`git remote get-url origin`).

   ```markdown
   ## Cross-repo PRs

   This change spans multiple repositories:

   | Repo | PR | Status |
   |------|----|--------|
   | **common** | **#142 (this PR)** | **open** |
   | hal | org/hal_repo#87 | open |
   | sim | org/sim_repo#203 | (not created) |
   ```

   Bold the current repo's row. For PRs not yet created in this batch, use `(not created)` — they will be filled in during Step 8.

4. Suggest a concise PR title (under 70 characters) following repo convention (`feat:`, `fix:`, `refactor:`, etc.). In multi-repo mode, titles can be consistent across repos but scoped to each repo's changes.
5. Present all titles and descriptions to the user for review. Wait for confirmation before proceeding.

### Step 7: Create the PR(s)

For each participating repo that needs a PR:

1. Write the description to `pr-description.md` in the repo root.
2. Create the PR:
   ```bash
   gh pr create --base <base-branch> --head <current-branch> --title "<title>" --body-file pr-description.md
   ```
3. Capture the PR URL and number.
4. Clean up `pr-description.md`.

### Step 8: Update cross-repo tables (multi-repo mode only)

After all PRs are created, do a second pass to fill in `(not created)` references:

1. Rebuild each PR's cross-repo table with all now-known PR numbers in `org/repo#number` format.
2. Update each PR body with `gh pr edit <number> --body-file <file>`.

### Step 9: Post-creation summary

Print a summary:

- **Single-repo:** PR URL, title, base branch, number of commits, files changed.
- **Multi-repo:** table of all created PRs:
  ```
  | Repo | Branch | PR | Base | Status |
  |------|--------|----|------|--------|
  | common | feat/gripper | #142 | develop | created |
  | hal    | feat/gripper | #87  | main    | created |
  | sim    | feat/gripper | #203 | develop | already existed (updated body) |
  ```

## Rules

- Do NOT include `Co-Authored-By` lines in PR descriptions.
- NEVER use destructive git commands.
- Always let the user review and edit PR titles and descriptions before submitting.
- Keep PR descriptions concise — the reviewer's time is limited.
- If there are uncommitted changes, ask whether to commit first (suggest `/commit`).
- If a branch has no commits ahead of its base, skip that repo and inform the user.
- Use `org/repo#number` format for cross-repo references so GitHub renders clickable links.
- In multi-repo mode, the cross-repo table should only appear when ≥2 repos actually participate. A lone PR gets no cross-repo section.
- The cross-repo table is always the **last** section of the PR body — below the template, summary, changes, and test plan.
