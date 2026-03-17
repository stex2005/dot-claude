---
description: Save or update the current plan to ~/.claude/plans/
allowed-tools: Bash(ls:*), Bash(mkdir:*), Read, Write, Edit, Glob, Grep
---

## Your task

Save the current conversation's plan to `~/.claude/plans/`.

### Steps

1. If the user specified a plan name, use that. Otherwise, infer a short name from the current work or ask.
2. Create the directory `~/.claude/plans/<name>/` if it doesn't exist.
3. If plan files already exist in the directory, read them first to understand what's there.
4. Write or update plan files in the directory. Structure them as numbered markdown files:
   - `00-<topic>.md`, `01-<topic>.md`, etc. for sequential steps or phases.
   - Each file should contain: goal, approach, status (done / in-progress / todo), and key details.
5. Confirm to the user what was saved and where.

### Rules

- Keep plan files concise and actionable -- focus on what needs to be done, not what was discussed.
- Preserve existing plan files that are still relevant. Update status fields rather than rewriting from scratch.
- Use markdown with clear headings: `## Goal`, `## Approach`, `## Status`, `## Notes`.
- Do NOT delete existing plan files unless the user explicitly asks.
