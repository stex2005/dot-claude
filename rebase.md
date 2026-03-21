---
description: Rebase the current feature branch on develop and push.
allowed-tools: Bash(git *), Bash(gh *), Bash(cd *), Bash(ls *), Bash(for *), Read, Glob
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: repo name or "all")

## Workspace detection

Detect the workspace mode before proceeding:

1. **Single-repo mode**: The current directory contains a `.git` folder → operate on this repo directly.
2. **Multi-repo mode**: The current directory does NOT contain `.git`, but has subdirectories that do → resolve which sub-repo(s) to operate on.
3. **Error**: Neither condition is met → inform the user and stop.

## Your task

Rebase the current feature branch on the base branch (`develop`, `main`, or `master` — detect from repo) and push.

### Step 0: Find the right repo(s)

**Single-repo mode:** Use the current directory. Skip repo resolution.

**Multi-repo mode:**
1. If the user provided a repo name, resolve it (try exact match, then substring match against subdirectory names).
2. If "all", find all sub-repos on the same branch name and process each.
3. If no argument, use the current working directory if it's inside a sub-repo, otherwise ask.

### Step 1: Preconditions

1. Verify the working tree is clean. If not, **stop and warn**.
2. Note the current branch name.
3. `git fetch origin <base-branch>`

### Step 2: Rebase

```bash
git rebase origin/<base-branch>
```

**If a conflict occurs:**
1. Stop and report which files conflict.
2. Do NOT auto-resolve.
3. Print instructions for manual resolution.

### Step 3: Push

```bash
git push --force-with-lease
```

**Always use `--force-with-lease`**, never `--force`.

### Step 4: Summary

```
Rebased <branch> on develop in <repo>
Old HEAD: <old-hash>
New HEAD: <new-hash>
Dropped commits (if any): <list>
```

## Rules

- NEVER use `git push --force`. Always use `--force-with-lease`.
- If the working tree is not clean, **refuse to proceed**.
- If a conflict occurs, **stop and report**. Do not auto-resolve.
