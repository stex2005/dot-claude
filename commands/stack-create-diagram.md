---
description: Create a draw.io diagram showing the PR stack across repos — steps, changes, and which repos are affected.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(for *), Bash(cd *), Bash(drawio:*), Bash(xdg-open:*), Read, Write, Edit, Glob, Grep
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: output file path)

## Preflight

Run the guard block from `~/.claude/docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack view --json` and the manifest are the only supported sources of
branch/step data — never fall back to hand-rolled `git branch --list '*/step*'`
globbing, even if the guard fails.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`~/.claude/docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. `MODE=single` means the
diagram shows steps for this repo only (column layout simplifies to a single column);
`MODE=multi` means the diagram shows the matrix of steps × repos, joined against
`$MANIFEST`. The manifest is read only when `MODE=multi`; in single-repo mode step
numbers come from `gh stack view --json`'s bottom-first `.branches` position instead
(Step 0.2 below).

## Your task

Generate a draw.io diagram that visualizes the entire PR stack — showing which steps exist, what each step changes, and (in multi-repo mode) which repos are involved.

> **Capability regression — fork branches are no longer represented.** The old
> `*/stepN-<name>` naming convention this command used to detect forks (independent work
> branching off step N that explicitly did *not* feed into step N+1, rendered as its own
> indented matrix row) is dead under `gh stack` auto-naming (`MM-DD-<slug>`), and more
> fundamentally, `gh stack` stacks are strictly linear — the manifest schema
> (`~/.claude/docs/stacked-pr-workflow.md#manifest-schema`) has no fork concept at all; `steps` is a
> flat, linear list keyed by `n`. This diagram now renders only the linear step chain. A
> user who needs fork-like work should make it **its own stack** instead — `gh stack`
> already supports multiple stacks per repo, addressed by stack number, so a fork can
> become a sibling stack rather than a row in this one (see
> `~/.claude/docs/stacked-pr-workflow.md#migration` for the same note). That is a plausible future
> direction, not something this command implements today.

### Step 0: Gather data

**`branches[].base` is a commit SHA, not a branch name — never use it for parent
edges.** Parent relationships come from array order in `gh stack view --json .branches`
(bottom-first, per `~/.claude/docs/gh-stack-json-reference.md`): step N's parent is step (N-1),
and step 1's parent is trunk. The same rule applies to the manifest's step order in
multi-repo mode.

1. Collect each repo's stack state:
   - **Single-repo mode:** run once, in the current directory:
     ```bash
     gh stack view --json 2>/dev/null; rc=$?
     ```
     If `rc` is `2`, there is no stack here — inform the user and stop; this is not an
     error. If `rc` is `6`, the checked-out branch belongs to several stacks — report
     `on <branch>, which belongs to multiple stacks — check out a non-trunk branch of
     the intended stack and re-run` and stop, also not a generic failure
     (`~/.claude/docs/stacked-pr-workflow.md#exit-codes`). Any other non-zero exit is a
     real failure — report it and stop.
   - **Multi-repo mode:** for each repo from `repos()`, run inside it (`cd "$WS/$repo"`):
     ```bash
     gh stack view --json 2>/dev/null; rc=$?
     ```
     `rc == 2` means "no stack in this repo" — record that and move on to the next repo,
     the same convention `/stack-status`'s Step 1 uses; it is not an error. `rc == 6`
     means that repo's current branch belongs to several stacks — record it as
     `multiple stacks — check out a non-trunk branch of the intended stack and re-run`
     and move on, also not an error
     (`~/.claude/docs/stacked-pr-workflow.md#exit-codes`). Collect every repo's parsed
     JSON before moving on — Step 0.3 needs all of them together.

   If **no repo** has a stack, inform the user and stop.

2. Determine step numbers, titles, and per-repo branches:
   - **Multi-repo mode:** read `$MANIFEST` via the manifest-read snippets in
     `~/.claude/docs/stacked-pr-workflow.md#manifest-reads` — `.steps[].n`, `.steps[].title`, and
     `.steps[].branches`. If `$MANIFEST` is absent, report that `/stack-status` can
     reconstruct it and stop — this command does not guess step numbers across repos on
     its own.
   - **Single-repo mode:** there is no manifest. Step N is the branch at the **1-indexed
     bottom-first position** N in `.branches` from Step 0.1's JSON — the same rule
     `/stack-status` and `/stack-commit` use. There is no step title beyond what the plan
     supplies (Step 0.4).

3. For each step `n` (ascending) and each repo participating in it (from the manifest's
   `.steps[$n].branches` in multi-repo mode; the single repo in single-repo mode),
   collect:
   - **Branch name**: from the manifest, or `.branches[n-1].name` from the Step 0.1 JSON
     in single-repo mode (same source as Step 0.2).
   - **One-line summary and diff stat**, compared against the correct parent — from
     array/step order, never `.base`:
     ```bash
     git log --oneline "$parent..$branch" | head -5
     git diff --stat "$parent..$branch"
     ```
     where `$parent` is step (n-1)'s branch for the same repo, or trunk for step 1
     (`.trunk[$r]` from the manifest, or `.trunk` from the Step 0.1 JSON in single-repo
     mode) — resolved the same way `/stack-create-summary` resolves it.
   - Read the changed files to understand what was done; write a brief 1-2 sentence
     summary focused on the *what* and *why*, not file counts.
   - **PR number, PR state, and merge state** — read directly off this branch's entry in
     the Step 0.1 JSON already collected for that repo, guarding the omitted `pr` key:
     ```bash
     jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.number // empty' <<<"$repo_json"
     jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .pr.state  // empty' <<<"$repo_json"
     jq -r --arg b "$branch" '.branches[] | select(.name==$b) | .isMerged' <<<"$repo_json"
     ```
     `pr` is omitted entirely (not null) when no PR exists yet — treat that as "no PR",
     never crash or render a blank number. `isMerged` is always present.
   - **Stale manifest entry**: if `$branch` has no matching entry in that repo's live
     `.branches` at all (renamed or deleted outside the manifest), the reads above return
     empty for every field, indistinguishable from "no PR yet" — check for this case
     explicitly and, per `/stack-status`'s Step 3, render that step/repo's node as
     unresolved in the diagram rather than as an unmerged step with no PR.
4. Read the plan:
   - **Multi-repo mode**: `.plan` from the manifest. If it is `""` (a bare-name stack,
     per `/stack-start`), there is no plan file — infer step titles/goals from commit
     messages and code changes.
   - **Single-repo mode**, or no plan recorded: fall back to `~/.claude/plans/`, else
     infer from commits.
5. Build a data structure, keyed by step number, listing each participating repo with
   its summary, PR number/state, and merge state:
   ```
   Step 1 "split files"    → [common (..., PR #142 open), hal (..., no PR)]
   Step 2 "gripper class"  → [common (..., PR #143 MERGED, merged), sim (..., PR #205 open)]
   Step 3 "planning logic" → [task_executor (..., no PR)]
   ```

### Step 1: Design the matrix layout

Create a **table/matrix** with repos as columns and steps as rows:

```
                        | common | hal | sim | task_executor | orchestrator |
  Step 1: split files   |  ✔ PR  |  ✔  |  —  |      —        |      —       |
  Step 2: gripper class |  ✔ PR  |  —  |  ✔  |      —        |      —       |
  Step 3: planning      |   —    |  —  |  —  |     ✔ PR      |      —       |
```

- **Column headers**: One per repo that has at least one step branch. Use short repo names (strip common prefixes if all repos share one).
- **Row headers**: Steps labeled `Step N: <title>`, in ascending order (1, 2, 3...) — array/step order, never `.base`.
- **Cells**: Each intersection shows whether that repo participates in that step, with a brief summary, PR number/state, and merge marker.
- **Empty cells**: Repos not involved in a step get an empty/dash cell.

### Step 2: Generate the draw.io XML

Use draw.io's native HTML table inside a single `mxCell` to produce a clean matrix. This renders as a proper grid without needing individual cells and arrows.

**Table structure:**

```html
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-size:12px;">
  <tr style="background:#dae8fc;">
    <th></th>
    <th>common</th>
    <th>hal</th>
    ...
  </tr>
  <tr>
    <td style="background:#dae8fc;font-weight:bold;">Step 1: split files</td>
    <td style="background:#d5e8d4;">Split node into pub/sub<br/>PR #142 (OPEN)</td>
    <td style="background:#fff2cc;">Extract HW config<br/>(no PR)</td>
    <td style="background:#f5f5f5;">—</td>
    ...
  </tr>
  <tr>
    <td style="background:#dae8fc;font-weight:bold;">Step 2: gripper class</td>
    <td style="background:#f5f5f5;color:#666;">Add GripperCommand<br/>PR #143 (merged)</td>
    ...
  </tr>
  ...
</table>
```

**Cell background colors by status** (merge state comes from `isMerged`, which is the
authoritative signal — it can be true even if the PR's own `.pr.state` string doesn't
say `MERGED`):
- **Merged** (`isMerged: true`): `#f5f5f5` (gray), gray text
- **PR open, not merged**: `#d5e8d4` (green)
- **No PR yet** (`pr` key absent, not merged): `#fff2cc` (yellow)
- **Not involved** (repo has no entry for this step): `#f5f5f5` (gray), dash

**Row header colors:**
- **Steps**: `#dae8fc` (blue)

**Cell content format:**
- Active cell, PR present: `<brief 1-line summary><br/>PR #N (<state>)`, and if
  `isMerged` is true append `, merged` (or show `merged` in place of the PR state when
  the state string itself is unhelpful) so a merged layer is visibly marked even when
  its `.pr.state` value is stale or absent.
- Active cell, no PR: `<brief summary><br/>(no PR)`
- Inactive cell: `—`

**mxCell for the table:**
```xml
<mxCell id="matrix" value="<HTML TABLE HERE>" style="text;html=1;overflow=fill;whiteSpace=wrap;fontSize=12;" vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="WIDTH" height="HEIGHT" as="geometry" />
</mxCell>
```

Set `width` and `height` to fit the table: ~180px per column + 200px for the row header column, ~80px per row + 40px for the header row.

### Step 3: Write the file

1. If the user provided an output path argument, use it. Otherwise suggest `$WS/docs/pr-stack-diagram.drawio`.
2. Ask the user for confirmation on file name.
3. Write the `.drawio` file.
4. Print a summary:
   - Total steps and repos involved
   - How many PRs exist vs missing, and how many steps are fully merged
   - Which steps span the most repos

### Draw.io XML rules

- CRITICAL: `<mxfile>` MUST have `host="app.diagrams.net"` attribute.
- CRITICAL: Every edge MUST have a child `<mxGeometry relative="1" as="geometry" />` element.
- CRITICAL: Use self-closing tags for `<mxCell ... />` and `<mxGeometry ... />` when they have no children.
- Use `&#xa;` for newlines inside `value` labels (not `<br>`).
- Use the standard draw.io XML structure:
  ```xml
  <mxfile host="app.diagrams.net" type="device">
    <diagram id="unique-id" name="PR Stack Overview">
      <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1100" pageHeight="850" math="0" shadow="0">
        <root>
          <mxCell id="0" />
          <mxCell id="1" parent="0" />
          <!-- shapes and edges here -->
        </root>
      </mxGraphModel>
    </diagram>
  </mxfile>
  ```
- Assign unique `id` attributes to every `mxCell`.
- Set `pageWidth` and `pageHeight` large enough to fit all columns and rows.
- Avoid overlapping nodes; use grid-aligned positions.

### Rules

- Always produce valid draw.io XML that can be opened without errors.
- Do NOT produce ASCII art, Mermaid, or PlantUML — only draw.io XML.
- If the stack is very large (>8 steps or >6 repos), ask the user if they want to filter or split into multiple diagrams.
- If no repo has a stack, inform the user and stop.
- Never fall back to `git branch --list '*/step*'` or any other hand-rolled branch
  discovery — the manifest (multi-repo mode) and `gh stack view --json`'s bottom-first
  position (single-repo mode) are the only sources, per the guard.
- Parent edges always come from step/array order, **never** from `.base`, which is a
  commit SHA, not a branch name.
- Every read of `.pr` must tolerate the key being entirely absent, never assume it is
  present or null.
- If the user asks to open the diagram, run `drawio <file>` (or `xdg-open <file>` as fallback). Do NOT open automatically.
