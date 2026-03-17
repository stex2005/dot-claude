---
description: Lint, format, and commit staged/unstaged changes on the current branch
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(git push:*), Bash(ruff check:*), Bash(ruff format:*), Bash(find:*)
---

## Your task

Lint, format, and commit changes on the current branch.

### Steps

0. **Find the git repo(s) with changes.** If the user provided an argument (e.g. `/commit myrepo`), use that as the repo directory name (relative to the working directory). Otherwise, the working directory may be a catkin/colcon workspace (`src/`) containing multiple git repos as subdirectories — run `find . -maxdepth 2 -name .git -type d` to locate repos, then check `git status` inside each to find which have uncommitted changes. Collect the list of repos with changes — there may be one or several. Perform the remaining steps **for each repo with changes**, running all git and ruff commands from that repo's root directory.
1. Identify all changed Python files (staged + unstaged) from `git status`.
2. Run `ruff check --fix` on the changed Python files.
3. Run `ruff format` on the changed Python files.
4. Show the user a summary of all changes across all repos (repo name, files changed, brief description of what changed).
5. Suggest **3 commit message options** following repo convention (`feat:`, `fix:`, `refactor:`, `style:`, `chore:`, `docs:`, `test:`). Each option should be concise and descriptive. If multiple repos have changes, suggest messages per repo.
6. Ask the user to pick one, edit, or provide their own.
7. Stage all changes: `git add -u` (plus any untracked files the user wants).
8. Commit with the chosen message.
9. Show `git log --oneline -3` to confirm.
10. Ask the user if they want to push. If yes: `git push origin <current_branch>`.

### Rules

- Do NOT include `Co-Authored-By` lines.
- If there are no changes to commit, inform the user and stop.
- If ruff reports unfixable errors, show them to the user and ask how to proceed.
