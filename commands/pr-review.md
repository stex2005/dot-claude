---
description: Conduct a comprehensive code review of a GitHub pull request.
allowed-tools: Bash(gh *), Bash(git *), Read, Write, Glob, Grep, AskUserQuestion
argument-hint: <pr-number> [ask]
---

## Setup

Arguments: `$ARGUMENTS`. The PR is the argument that is not `ask` (a number, URL or branch). If `ask` is present (any position, case-insensitive), run in **ask mode** (see Interactive Triage).

Pull the information about the PR using `gh pr view <pr> --comments` and `gh pr diff <pr>`.

## Pre-Review Checklist

Before diving into the code, verify:

- **Build & Tests**: Verify that the build/tests pass.
- **PR Metadata**:
  - Is the title and description clear and complete?
  - Does the PR link to an issue for traceability?
  - Is the change size appropriate?
- **Understanding the Objective**:
  - Read the linked issue title and description (use `gh` to pull issue details).
  - For bug fixes: understand the root cause being addressed.

## Code Review Checklist

### Scope & Relevance

- Are there unrelated formatting changes, refactorings, or fixes that should be separate PRs?
- Do irrelevant changes obscure the actual changes being reviewed?

### Code Quality & Design

- **Naming**: Are classes, methods, functions, parameters named clearly and following conventions?
- **Design Principles**: Does the code respect SOLID? Follow existing patterns? Avoid DRY violations?
- **Code Style**: Magic numbers/strings extracted? Dead or commented-out code removed?
- **Type Safety**: Are parameters and return types annotated (in typed/type-hinted languages)?

### Testing & Coverage

- Does the PR include tests? Is new code covered?
- Do tests cover edge cases and error scenarios?
- Are tests testing behavior rather than implementation details?

### Architecture & Structure

- Are new/moved files in the right location with appropriate names?
- Are new dependencies justified, version-pinned, and license-compatible?
- Are backward-incompatible changes documented?
- Are design decisions reversible?

### Operational Concerns

- **Logging**: Appropriate levels? No sensitive data logged?
- **Error Handling**: Graceful handling? Meaningful messages? Resource cleanup?
- **Performance**: N+1 queries? Inefficient algorithms? Appropriate caching?

### Security & Data

- Input validated and sanitized?
- No hardcoded secrets or credentials?
- Parameterized queries? XSS/CSRF protections?
- PII handled appropriately? Data migrations safe and reversible?

### Documentation

- Complex algorithms or business logic commented?
- Public APIs documented?
- README or user-facing docs need updates?
- Breaking changes documented?

## Review Communication Guidelines

When providing feedback:

- Be specific and actionable — include code examples when helpful.
- Prioritize feedback using RFC 2119 language: MUST, SHOULD, MAY.
- Assume competence. Provide rationale. Criticize the code, not the person.

## Interactive Triage (ask mode only)

Skip this section unless `ask` was passed.

After drafting all findings, and before printing the review, walk through them one at a time, MUST first, then SHOULD, then MAY. For each finding, call `AskUserQuestion` with one question that stands on its own:

- Question text: `[<SEVERITY> <i>/<n>] <file>:<line> — <one-line finding>`, plus the rationale and the suggested fix in a sentence or two.
- Options: **Keep** (as written), **Change severity** (then ask MUST/SHOULD/MAY in a follow-up question), **Reword** (the user gives the new text via "Other" or a follow-up), **Drop**.
- Put the relevant code snippet in the `preview` field when it helps.

Batch up to 4 findings per `AskUserQuestion` call to keep the pace up, but never mix severities in one call. Apply each answer before moving on; notes the user adds are folded into the finding. Do not re-ask about a finding once answered.

The final output contains only the kept findings, with their final severity and wording; the overall status is recomputed from them (e.g. no MUST left → no longer "needs work" on MUST grounds). End with a one-line tally: kept / changed / reworded / dropped.

## Output

Print the review to the console with:
- Overall status at the top (ready to merge, needs work, etc.)
- Grouped findings by severity (MUST / SHOULD / MAY)
- Specific line references where applicable
