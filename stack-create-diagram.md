---
description: Create a draw.io diagram showing the PR stack across repos — steps, changes, and which repos are affected.
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(for *), Bash(cd *), Bash(drawio:*), Bash(xdg-open:*), Read, Write, Edit, Glob, Grep
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional: output file path)

## Workspace detection

Detect the workspace mode before proceeding:

1. **Single-repo mode**: The current directory contains a `.git` folder → diagram shows steps for this repo only (column layout simplifies to a single column).
2. **Multi-repo mode**: The current directory does NOT contain `.git`, but has subdirectories that do → diagram shows the matrix of steps × repos.
3. **Error**: Neither condition is met → inform the user and stop.

## Your task

Generate a draw.io diagram that visualizes the entire PR stack — showing which steps exist, what each step changes, and (in multi-repo mode) which repos are involved.

### Step 0: Gather data

**Single-repo mode:**
1. Find step branches: `git branch --list '*/step*'`
   If no branches match, inform the user and stop.
2. For each step branch, collect:
   - Branch name
   - One-line summary: `git log --oneline <base>..<branch> | head -5`
   - Diff stat: `git diff --stat <base>..<branch>`
   - Whether a PR exists: `gh pr list --head <branch> --json number,state,url`
3. Read the plan files from `~/.claude/plans/` to get step titles and goals.

**Multi-repo mode:**
1. Scan all sub-repos for step branches:
   ```bash
   for d in */; do (cd "$d" && branches=$(git branch --list '*/step*' 2>/dev/null); [ -n "$branches" ] && echo "REPO:${d%/}" && echo "$branches"); done
   ```
   If no branches match, inform the user and stop.
2. For each repo with step branches, collect per step:
   - Branch name
   - One-line summary: `git log --oneline <base>..<branch> | head -5`
   - Diff stat: `git diff --stat <base>..<branch>`
   - Whether a PR exists: `gh pr list --head <branch> --json number,state,url`
3. Read the plan files from `~/.claude/plans/` to get step titles and goals.
4. Build a data structure:
   ```
   Step 1 "split files"   → [common (4 files, +120 -80, PR #142 open), hal (2 files, +40 -20, no PR)]
   Step 2 "gripper class"  → [common (3 files, +90 -50, PR #143 open), sim (1 file, +30 -10, PR #205 open)]
   Step 3 "planning logic" → [task_executor (6 files, +200 -100, no PR)]
   ```

### Step 1: Design the layout

Use a **matrix layout** with steps as rows and repos as columns:

```
            | common | hal | sim | task_executor | orchestrator |
  Step 1    |  [X]   | [X] |     |               |              |
  Step 2    |  [X]   |     | [X] |               |              |
  Step 3    |        |     |     |     [X]        |              |
```

- **Column headers**: One per repo that has at least one step branch. Use short repo names (strip common prefixes if all repos share one).
- **Row headers**: One per step, labeled `Step N: <slug>` with the goal from the plan.
- **Cells**: A card at each intersection where that repo participates in that step.
- **Arrows**: Vertical arrows between consecutive step cells within the same repo, showing the stacked PR chain.

### Step 2: Generate the draw.io XML

**Layout constants:**
- Column width: 200px, Row height: 140px
- Header row height: 50px, Header column width: 180px
- Cell padding: 10px
- Starting position: x=40, y=40

**Element styles:**

- **Column headers** (repo names): `rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontStyle=1;fontSize=13;`
- **Row headers** (step labels): `rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontStyle=1;fontSize=12;align=left;spacingLeft=8;`
- **Active cells** (repo participates in step): Rounded rectangle containing:
  - Files changed count and lines ±
  - PR link if exists (e.g., `PR #142 ✓` for open, `PR #142 ✗` for merged)
  - Style: `rounded=1;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;fontSize=11;verticalAlign=top;spacingTop=4;`
- **PR exists**: Green stroke (`strokeColor=#82b366;strokeWidth=2;`)
- **No PR yet**: Dashed border (`dashed=1;strokeColor=#d6b656;`)
- **Merged PR**: Gray fill (`fillColor=#f5f5f5;strokeColor=#999999;fontColor=#999999;`)
- **Chain arrows** (vertical, between consecutive steps in same repo): `edgeStyle=orthogonalEdgeStyle;strokeColor=#6c8ebf;strokeWidth=2;`

**Cell value format** (use `&#xa;` for newlines):
```
<files-changed> files  +<added> -<removed>&#xa;PR #<number> (<state>)
```
or if no PR:
```
<files-changed> files  +<added> -<removed>&#xa;(no PR)
```

### Step 3: Write the file

1. If the user provided an output path argument, use it. Otherwise suggest `docs/pr-stack-diagram.drawio`.
2. Ask the user for confirmation on file name.
3. Write the `.drawio` file.
4. Print a summary:
   - Total steps and repos involved
   - How many PRs exist vs missing
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
- If no step branches exist in any repo, inform the user and stop.
- If the user asks to open the diagram, run `drawio <file>` (or `xdg-open <file>` as fallback). Do NOT open automatically.
