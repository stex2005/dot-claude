---
description: Rebase the current feature branch on develop and push.
allowed-tools: Bash(git *), Bash(gh *), Bash(cd *), Bash(ls *), Bash(for *), Read, Glob
---

## Context

- Workspace: /home/stefano/repos/development_ws/src (NOT a git repo itself)
- Arguments: $ARGUMENTS (optional: repo name or "all")

**IMPORTANT:** The workspace contains multiple independent git repos as subdirectories under `src/`. You MUST `cd` into the correct repo before running any git commands.

## Your task

Rebase the current feature branch on `develop` and push.

### Step 0: Find the right repo(s)

1. If the user provided a repo name, resolve it (shorthands: `te` = `unloading_robot_task_executor`, `common` = `unloading_robot_common`, `kuka` = `kuka_experimental`, `debugger` = `unloading_robot_debugger`).
2. If "all", find all repos on the same branch name and process each.
3. If no argument, use the current working directory.

### Step 1: Preconditions

1. Verify the working tree is clean. If not, **stop and warn**.
2. Note the current branch name.
3. `git fetch origin develop`

### Step 2: Rebase

```bash
git rebase origin/develop
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
