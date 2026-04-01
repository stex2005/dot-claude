---
description: Lint, format, and create a pull request for the current branch.
allowed-tools: Bash(git *), Bash(gh *), Bash(ruff *), Bash(find *), Read, Write, Edit
argument-hint: [base-branch]
---

## Your task

Lint, format, and create a pull request for the current branch.

### Steps

0. **Find the git repo.** The working directory should be a git repo (has `.git`). If not, check if it's a workspace with sub-repos and ask the user which repo to use. All subsequent commands run from the repo root.

1. **Identify the current branch and base branch.**
   - Current branch: `git branch --show-current`. If on `main`, `master`, or `develop`, warn the user and stop — PRs should be created from feature branches.
   - Base branch: use `$ARGUMENTS` if provided. Otherwise, detect the default branch via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, falling back to whichever of `main`, `master`, or `develop` exists.

2. **Check for existing PR.** Run `gh pr list --head <current-branch> --json number,url,state`. If an open PR already exists, show it and ask the user if they want to update it instead.

3. **Lint and format changed files.**
   - Identify all changed Python files vs the base branch: `git diff --name-only <base-branch>...HEAD -- '*.py'` plus any unstaged/staged changes.
   - Run `ruff check --fix` on the changed Python files.
   - Run `ruff format` on the changed Python files.
   - If ruff reports unfixable errors, show them to the user and ask how to proceed.
   - If linting/formatting produced changes, stage and commit them with message `style: lint and format`.

4. **Ensure branch is pushed.** Run `git push -u origin <current-branch>`. If the push fails, show the error and ask the user how to proceed.

5. **Gather context for the PR description.**
   - Run `git log --oneline <base-branch>..HEAD` to see all commits on this branch.
   - Run `git diff <base-branch>...HEAD --stat` to see the scope of changes.
   - If the diff is > 400 lines, warn the user and suggest splitting.

6. **Draft the PR.**
   - Check if the repo has a pull request template (`.github/PULL_REQUEST_TEMPLATE.md` or `.github/pull_request_template.md`). If so, use it as the structure.
   - Otherwise, draft a description with:
     - **Summary**: 1-3 bullet points explaining what this PR does and why.
     - **Changes**: brief list of key changes.
     - **Test plan**: how to verify the changes work.
   - Suggest a concise PR title (under 70 characters) following repo convention (`feat:`, `fix:`, `refactor:`, etc.).
   - Present the title and description to the user for review. Wait for confirmation before proceeding.

7. **Create the PR.**
   - Write the description to a temp file `pr-description.md` in the repo root.
   - Create the PR:
     ```bash
     gh pr create --base <base-branch> --head <current-branch> --title "<title>" --body-file pr-description.md
     ```
   - Capture and display the PR URL.
   - Clean up `pr-description.md`.

8. **Post-creation.** Show the PR URL and a summary: title, base branch, number of commits, files changed.

### Rules

- Do NOT include `Co-Authored-By` lines in PR descriptions.
- NEVER use destructive git commands.
- Always let the user review and edit the PR title and description before submitting.
- Keep PR descriptions concise — the reviewer's time is limited.
- If there are uncommitted changes, ask the user if they want to commit first (suggest using `/commit`).
- If the branch has no commits ahead of the base, inform the user and stop.
