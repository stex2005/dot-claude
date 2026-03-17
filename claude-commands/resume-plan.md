---
description: Resume work on a saved plan from ~/.claude/plans/
allowed-tools: Bash(ls:*), Read, Write, Edit, Glob, Grep, Agent, EnterPlanMode, ExitPlanMode
---

## Your task

Resume work on an existing plan saved in `~/.claude/plans/`.

### Steps

1. List available plan directories under `~/.claude/plans/` using the Glob tool.
2. If the user specified a plan name in the arguments, use that. Otherwise, show the list and ask which plan to resume.
3. Read all plan files in the chosen directory, in alphabetical order.
4. Enter plan mode using `EnterPlanMode` with the plan context loaded.
5. Summarize:
   - Overall goal of the plan
   - Full status table of all steps (done / in-progress / TODO)
   - Automatically identify the **first TODO step** (the next step to implement)
6. Propose starting from that first incomplete step. Do NOT ask which step — just say "Resuming from Step N: <description>" and proceed with planning that step.
7. Once the approach is ready, exit plan mode with `ExitPlanMode` and proceed with implementation.

### Rules

- Always re-read the plan files at the start -- they may have been updated outside this session.
- When completing a step, update the relevant plan file to reflect progress.
- If a step is blocked or needs clarification, flag it to the user before proceeding.
