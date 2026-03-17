---
description: Start a new plan and save it to ~/.claude/plans/
allowed-tools: Bash(ls:*), Bash(mkdir:*), Read, Write, Edit, Glob, Grep, Agent
---

## Your task

Create a new plan for the user's goal and save it to `~/.claude/plans/`.

### Steps

1. Understand what the user wants to accomplish. If the goal is unclear, ask.
2. Research the codebase as needed to inform the plan (read relevant files, configs, architecture).
3. Break the work into sequential phases or steps.
4. Choose a short plan name (lowercase, hyphenated). If the user provided one, use that.
5. Create the directory `~/.claude/plans/<name>/`.
6. Write plan files as numbered markdown files:
   - `00-<topic>.md`, `01-<topic>.md`, etc.
   - Each file covers one phase or major step.
7. Present the plan summary to the user for approval before proceeding with any implementation.

### Plan file format

Each plan file should follow this structure:

```markdown
## Goal

What this phase aims to achieve.

## Approach

How to accomplish it -- key decisions, files to modify, techniques.

## Status

todo | in-progress | done

## Notes

Any caveats, open questions, or dependencies on other phases.
```

### Rules

- Keep plans practical and grounded in the actual codebase -- not abstract.
- Each phase should be independently completable in a single session.
- Flag risks or unknowns explicitly in the Notes section.
- Do NOT start implementation until the user approves the plan.
