---
description: Generate a text summary of the entire step stack — goals, repos, changes, status, and features per step.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Read, Write, Edit, Glob, Grep
---

## Context

- Workspace: /home/stefano/repos/development_ws/src (NOT a git repo itself)
- Arguments: $ARGUMENTS (optional: output file path)
- Repo shorthands: `task_executor` → `unloading_robot_task_executor`, `common` → `unloading_robot_common`, `hal` → `unloading_robot_hal`, `sim` → `unloading_robot_sim`, `orchestrator` → `unloading_robot_process_orchestrator`

**IMPORTANT:** The workspace contains multiple independent git repos as subdirectories under `src/`. You MUST `cd` into the correct repo before running any git commands.

## Your task

Generate a structured text summary of the entire PR stack across all repos.

### Step 0: Gather data

1. Scan all repos for step branches using `*/step*`:
   ```bash
   for d in */; do (cd "$d" && branches=$(git branch --list '*/step*' 2>/dev/null); [ -n "$branches" ] && echo "REPO:${d%/}" && echo "$branches"); done
   ```
   If no branches match, inform the user and stop.
2. For each repo with step branches, collect per step:
   - Branch name
   - Commit messages — compare against the correct parent:
     - step1: `git log --oneline develop..step1`
     - stepN: `git log --oneline step(N-1)..stepN`
   - Read the changed files to understand what was done
   - PR status: `gh pr list --head <branch> --json number,state,url`
3. Read the plan files from `~/.claude/plans/` to get step goals and status.

### Step 1: Generate the summary

For each step (sorted by step number), output the following template:

```markdown
## Step <N>: <slug>

**Goal:** <what this step aims to achieve, from the plan>

**Status:** <todo | in-progress | done | PR open | PR merged> (include PR links if they exist)

**Repos and changes:**

- **<repo-short-name>**: <1-2 sentence summary of what changed in this repo>
- **<repo-short-name>**: <1-2 sentence summary of what changed in this repo>

**Features implemented:**

- <concrete feature or behavior that was added/changed>
- <concrete feature or behavior that was added/changed>
- ...
```

Guidelines for each section:
- **Goal**: Take from the plan file. If no plan exists, infer from commit messages and code changes.
- **Status**: Check plan status field AND PR state. Combine them (e.g., "in-progress, PR #142 open").
- **Repos and changes**: One bullet per repo that has this step branch. Summarize what that repo's changes do — not file counts, but the actual substance.
- **Features implemented**: List the concrete capabilities or behaviors that this step delivers. Read the actual code changes to determine this — don't just rephrase commit messages. Focus on what a user or developer would notice.

### Step 2: Output

1. Write the summary to a file. If the user provided an output path argument, use it. Otherwise use `docs/stack-summary.md`.
2. Print the full summary to the console so the user can copy-paste it directly into Confluence. The markdown format used above (headers, bold, bullet lists) pastes cleanly into Confluence's editor.

## Rules

- If no step branches exist, inform the user and stop.
- Keep summaries concise — this is an overview, not a changelog.
- Use short repo names (strip `unloading_robot_` prefix) for readability.
- Compare each step against its parent branch (step(N-1)), not against develop, to show only that step's changes.
