---
description: Analyze all existing plans (built-in and superpowers) and prune obsolete/superseded/irrelevant ones. Asks permission before deleting.
allowed-tools: Bash(ls:*), Bash(rm:*), Bash(find:*), Bash(wc:*), Read, Glob, Grep
---

## Context

- Plans directory: `~/.claude/plans/`
- Superpowers plans: `~/.claude/plugins/cache/claude-plugins-official/superpowers/*/docs/superpowers/plans/`
- Superpowers specs: `~/.claude/plugins/cache/claude-plugins-official/superpowers/*/docs/superpowers/specs/`
- Arguments: $ARGUMENTS (optional: "all", "plans", "specs", or a specific filename)

## Your task

Analyze all saved plans and specs, identify which are obsolete, and ask the user before deleting.

### Step 1: Discover all plan files

1. List all `.md` files in `~/.claude/plans/` (flat files and directories with numbered sub-files).
2. List all `.md` files in the superpowers plans and specs directories.
3. Report the total count per location.

### Step 2: Read and classify each plan

Read each plan file and classify it into one of these categories:

| Category | Criteria |
|----------|----------|
| **DONE** | Plan explicitly says "DONE", all steps marked complete, or describes work that is clearly finished |
| **SUPERSEDED** | A newer plan covers the same topic, or the plan references an approach that was replaced |
| **STALE** | Plan is older than 2 months with no recent activity, references files/branches that no longer exist, or describes work on a feature that has since shipped |
| **ACTIVE** | Plan has TODO or in-progress steps and appears to describe current or recent work |
| **UNCLEAR** | Cannot determine status from the plan content alone |

**Classification heuristics:**
- Plans starting with "DONE" or "# DONE" → **DONE**
- Plans referencing branches: check if the branch still exists with `git branch -a --list '<branch>'` in the relevant repo
- Plans with all steps marked `[x]` or status: done → **DONE**
- Plans about features you can confirm exist in the codebase → **DONE** or **STALE**
- When in doubt, classify as **UNCLEAR** (never auto-delete unclear plans)

### Step 3: Present findings

Show a summary table grouped by category:

```
## Plan Analysis Results

### ~/.claude/plans/ (N files)

| # | File | Category | Reason |
|---|------|----------|--------|
| 1 | sleepy-jumping-cook.md | DONE | Explicitly says "DONE — no further changes needed" |
| 2 | ... | STALE | References branch feature/xyz which no longer exists |

### Superpowers plans (N files)

| # | File | Category | Reason |
|---|------|----------|--------|

### Superpowers specs (N files)

| # | File | Category | Reason |
|---|------|----------|--------|
```

### Step 4: Propose deletions

List only the files classified as **DONE**, **SUPERSEDED**, or **STALE** and ask:

> "I recommend deleting the N files above marked DONE/SUPERSEDED/STALE. Want me to:
> 1. Delete all of them
> 2. Delete only specific categories (DONE / SUPERSEDED / STALE)
> 3. Let me pick individually
> 4. Skip — don't delete anything"

**Wait for the user's response before deleting anything.**

### Step 5: Delete approved files

For each approved file:
- If it's a flat `.md` file: `rm <path>`
- If it's a directory with sub-files: `rm -r <path>`

Report what was deleted and what remains.

## Rules

- NEVER delete a file without explicit user approval.
- NEVER delete files classified as **ACTIVE** or **UNCLEAR** unless the user specifically names them.
- For superpowers plugin files, **warn** that deleting them may cause issues if the plugin expects them, but allow deletion if the user confirms.
- If the user provided a specific filename as argument, analyze and prompt for just that file.
- Read the FULL content of each plan before classifying — don't rely on filenames alone.
