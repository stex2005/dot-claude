---
description: Generate or update a text summary of the entire step stack — goals, repos, changes, status, risks, and features per step.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(for *), Bash(cd *), Read, Write, Edit, Glob, Grep
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: output file path)
- Repo shorthands: `task_executor` → `unloading_robot_task_executor`, `common` → `unloading_robot_common`, `hal` → `unloading_robot_hal`, `sim` → `unloading_robot_sim`, `orchestrator` → `unloading_robot_process_orchestrator`

## Preflight

Run the guard block from `docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack view --json` and the manifest are the only supported sources of
branch/step data — never fall back to hand-rolled `git branch --list '*/step*'`
globbing, even if the guard fails.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is read
only when `MODE=multi`; in single-repo mode there is no manifest and step numbers come
from `gh stack view --json`'s bottom-first `.branches` position instead (Step 1.2 below).

## Your task

Generate or update a structured text summary of the entire PR stack across all repos. If a summary file already exists, update it in place; otherwise create it from scratch.

### Step 0: Check for existing summary

1. If the user provided a file path argument, check if it exists.
2. Otherwise, check for `$WS/docs/stack-summary.md`.
3. If found, read it — you will update it in Step 2. If not found, you will create it fresh.

### Step 1: Gather data

1. Collect each repo's stack state:
   - **Single-repo mode:** run once, in the current directory:
     ```bash
     gh stack view --json 2>/dev/null; rc=$?
     ```
     If `rc` is `2`, there is no stack here — inform the user and stop; this is not an
     error. Any other non-zero exit is a real failure — report it and stop.
   - **Multi-repo mode:** for each repo from `repos()`, run inside it (`cd "$WS/$repo"`):
     ```bash
     gh stack view --json 2>/dev/null; rc=$?
     ```
     `rc == 2` means "no stack in this repo" — record that and move on to the next repo,
     the same convention `/stack-status`'s Step 1 uses; it is not an error. Collect every
     repo's parsed JSON before moving on — Step 1.3 needs all of them together.

   If **no repo** has a stack, inform the user and stop.

2. Determine step numbers, titles, and per-repo branches:
   - **Multi-repo mode:** read `$MANIFEST` via the manifest-read snippets in
     `docs/stacked-pr-workflow.md#manifest-reads` — `.steps[].n`, `.steps[].title`, and
     `.steps[].branches` give the step list, its titles, and which repo has which branch
     at each step. If `$MANIFEST` is absent, report that `/stack-status` can reconstruct
     it and stop — this command does not guess step numbers across repos on its own.
   - **Single-repo mode:** there is no manifest. The step number for a branch is its
     **1-indexed bottom-first position** in `.branches` from Step 1.1's JSON — the same
     rule `/stack-status` and `/stack-commit` use. There are no step titles beyond what
     the plan supplies (Step 1.4).

3. For each step `n` (sorted ascending) and each repo participating in it (from the
   manifest's `.steps[$n].branches` in multi-repo mode; the single repo in single-repo
   mode), collect:
   - **Branch name**: from the manifest (`.steps[] | select(.n==$n) | .branches[$r]`) in
     multi-repo mode, or `.branches[n-1].name` from the Step 1.1 JSON in single-repo mode.
   - **Commit messages**, compared against the correct parent. **Never use `.base`** —
     it is a commit SHA, not a branch name (`docs/gh-stack-json-reference.md`); parent
     branches come from step order instead:
     - step 1: compare against trunk — `.trunk[$r]` from the manifest, or `.trunk` from
       the Step 1.1 JSON in single-repo mode.
     - step N (N>1): compare against step (N-1)'s branch for the same repo, resolved the
       same way as this step's branch above.
     ```bash
     git log --oneline "$parent..$branch"
     ```
   - Read the changed files to understand what was done.
   - **PR status and merge state**: read directly off this branch's entry in the Step
     1.1 JSON already collected for that repo — do not make a separate `gh pr list`
     call:
     ```bash
     jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.number // empty' <<<"$repo_json"
     jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.state  // empty' <<<"$repo_json"
     jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.url   // empty' <<<"$repo_json"
     jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .isMerged' <<<"$repo_json"
     ```
     `pr` is omitted entirely (not null) when no PR exists yet — every read above must
     tolerate that absence and report "no PR yet" rather than erroring or printing a
     blank number.
   - **Stale manifest entry**: if `$branch` has no matching entry in that repo's live
     `.branches` at all (renamed or deleted outside the manifest), the reads above return
     empty for every field, indistinguishable from "no PR yet" — check for this case
     explicitly and, per `/stack-status`'s Step 3, show that step/repo as unresolved in
     the summary rather than reporting it as an unmerged step with no PR.
4. Read the plan:
   - **Multi-repo mode**: read `.plan` from the manifest (manifest-reads anchor). If it
     is the empty string `""` (a stack started from a bare name, per `/stack-start`),
     there is no plan file — infer step goals from commit messages and code changes,
     same as the "no plan exists" guideline below.
   - **Single-repo mode**, or no plan recorded: fall back to `~/.claude/plans/` if a
     matching plan file can be found there; otherwise infer from commits and changes.

### Step 2: Generate or update the summary

For each step (sorted by step number), use the following template:

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

**Main risks:**

- <risk or concern about this step's changes — e.g., untested edge cases, API breaking changes, concurrency issues, assumptions that may not hold>
- ...

**Notes:**

- <any additional context, caveats, or follow-up items>
```

Guidelines for each section:
- **Goal**: Take from the plan file. If no plan exists, infer from commit messages and code changes.
- **Status**: Check the plan's status field AND the PR/merge data read in Step 1.3. Combine them (e.g., "in-progress, PR #142 open"). A branch with no `pr` key yet is "no PR yet", not an error.
- **Repos and changes**: One bullet per repo that has this step branch. Summarize what that repo's changes do — not file counts, but the actual substance.
- **Features implemented**: List the concrete capabilities or behaviors that this step delivers. Read the actual code changes to determine this — don't just rephrase commit messages. Focus on what a user or developer would notice.
- **Main risks**: Identify risks by reading the actual code changes. Look for: untested paths, breaking API changes, race conditions, hardcoded assumptions, missing error handling, or integration risks across repos. If a step is low-risk, say so briefly rather than omitting the section.
- **Notes**: Optional. Only include if there are meaningful caveats, follow-ups, or context not captured elsewhere.

#### When updating an existing summary

- **Preserve** existing wording in sections where nothing changed — don't rewrite unnecessarily.
- **Update** status, repos/changes, features, and risks for steps that have new commits.
- **Add** new steps that weren't in the previous summary.
- **Keep** steps whose branches were fully merged and cleaned up (`isMerged` true and the branch no longer present in `gh stack view --json`), but mark status as "merged and cleaned up".
- After updating, call out what changed: which steps were updated, which are new, which were completed.

### Step 3: Output

1. Write or update the summary file. If the user provided an output path argument, use it. Otherwise use `$WS/docs/stack-summary.md`.
2. Print the full summary to the console so the user can copy-paste it directly into Confluence. The markdown format used above (headers, bold, bullet lists) pastes cleanly into Confluence's editor.

## Rules

- If no repo has a stack (Step 1 finds nothing), inform the user and stop.
- Never fall back to `git branch --list '*/step*'` or any other hand-rolled branch
  discovery — the manifest (multi-repo mode) and `gh stack view --json`'s bottom-first
  position (single-repo mode) are the only sources, per the guard.
- Keep summaries concise — this is an overview, not a changelog.
- Use short repo names (strip `unloading_robot_` prefix) for readability.
- Compare each step against its parent branch — step (N-1)'s branch, or trunk for step
  1 — resolved via the manifest/array position, **never** via `.base`, which is a commit
  SHA, not a branch name.
- Every read of `.pr` must tolerate the key being entirely absent, never assume it is
  present or null.
