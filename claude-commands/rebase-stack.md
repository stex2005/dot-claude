---
description: Rebase the entire chain of step branches when the base branch moves forward.
allowed-tools: Bash(git *), Bash(ls *), Bash(for *), Bash(cd *), Read, Glob
---

## Context

- Workspace: /home/stefano/repos/development_ws/src (NOT a git repo itself)
- Arguments: $ARGUMENTS (optional: repo name)

**IMPORTANT:** The workspace contains multiple independent git repos as subdirectories under `src/`. You MUST `cd` into the correct repo before running any git commands.

## Your task

Rebase the full chain of step branches so they are up to date with the base branch (`develop`).

### Step 0: Find the right repo

1. If the user provided a repo name argument, resolve it (same shorthands as `/commit-stack`).
2. If no argument, scan repos for step branches and ask which repo to operate on.

All subsequent commands MUST run inside the resolved repo directory.

### Step 1: Map the stack

1. Find all step branches: `git branch --list 'feature/stefano/refactor/step*'`
2. Sort by step number.
3. Determine the base: `develop` (or ask if unclear).
4. Fetch latest: `git fetch origin`

### Step 2: Check preconditions

1. Verify the working tree is clean. If not, **stop and warn** — do not proceed with uncommitted changes.
2. Note the current branch so we can return to it at the end.

### Step 3: Rebase the chain in order

Process each step branch sequentially, bottom to top:

```
git checkout step1-<slug> && git rebase develop
git checkout step2-<slug> && git rebase step1-<slug>
git checkout step3-<slug> && git rebase step2-<slug>
...
```

**If a rebase conflict occurs:**
1. **Stop immediately.**
2. Report which step branch has the conflict and what files are affected.
3. Do NOT attempt to resolve conflicts automatically.
4. Leave the repo in the conflicted state so the user can resolve manually.
5. Print instructions for the user:
   ```
   Conflict on: step2-gripper-class (rebasing onto step1-split-files)
   Conflicting files: <list>

   To resolve:
     1. Fix conflicts in the listed files
     2. git add <resolved-files>
     3. git rebase --continue
     4. Then re-run /rebase-stack to continue the rest of the chain
   ```

### Step 4: Push updated branches

After all rebases succeed, ask the user if they want to force-push the updated branches:

```bash
git push --force-with-lease origin step1-<slug> step2-<slug> step3-<slug>
```

**Always use `--force-with-lease`**, never `--force`.

### Step 5: Return and summarize

1. Check out the branch the user was on before the rebase.
2. Print a summary:

```
## Rebase complete for <repo>

| Step | Branch | Rebased onto | Result |
|------|--------|-------------|--------|
| 1    | step1-split-files | develop | ok |
| 2    | step2-gripper | step1-split-files | ok |
| 3    | step3-planning | step2-gripper | ok |

Pushed: yes / no (awaiting confirmation)
```

## Rules

- NEVER use `git push --force`. Always use `--force-with-lease`.
- If the working tree is not clean, **refuse to proceed**.
- If a conflict occurs, **stop and report**. Do not auto-resolve.
- Always ask before pushing force-updated branches.
- Return to the user's original branch when done.
