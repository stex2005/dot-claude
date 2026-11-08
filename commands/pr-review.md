---
description: Conduct a comprehensive code review of a GitHub pull request.
allowed-tools: Bash(gh *), Bash(git *), Read, Write, Glob, Grep, AskUserQuestion
argument-hint: <pr-number> [ask]
---

## Setup

Arguments: `$ARGUMENTS`. The PR is the argument that is not `ask` (a number, URL or branch). If `ask` is present (any position, case-insensitive), run in **ask mode** (see Interactive Triage).

Pull the information about the PR using `gh pr view <pr> --comments` and `gh pr diff <pr>`.

If no PR is named, use the one reviewed earlier in this conversation. If its head commits haven't changed, triage those findings instead of reviewing again.

When asked to include companion or sibling PRs, take the list from the PR descriptions. Also look for same-named branches in the other repos: a companion with a branch but no PR has no CI and can't be reviewed, which is a finding in itself.

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
  - If it's described as a refactor or "no behaviour change": trace each output field back to its producer on the base branch, and show old vs new in a table.
  - If the arguments or thread include an agreed design: check each agreed point against the code and report any that are missing.

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
- Before proposing a fix, read the code it touches and check that it works, for example that a "return failure" has a failure field to return.

## Interactive Triage (ask mode only)

Skip this section unless `ask` was passed.

After drafting all findings, and before printing the review, walk through them one at a time, MUST first, then SHOULD, then MAY. Each finding gets its own `AskUserQuestion` call with up to two questions that stand on their own (the user may not see earlier output):

1. **How to move forward** (header `Resolution`). Question text: `[<SEVERITY> <i>/<n>] <file>:<line> — <finding>`, plus why it matters in a sentence. Options are the concrete ways forward you would actually propose for *this* finding, recommended one first and marked "(Recommended)":
   - 1–2 specific fixes (e.g. "Extract to a constant in params.py", "Guard with a bounded wait") — each with its trade-off in the description and the proposed code in `preview`.
   - **Follow-up issue** — fine to merge now, track the rest separately.
   - **Drop** — not a real problem / not worth raising.
   The user can always answer "Other" with their own direction.
2. **Severity** (header `Severity`): MUST / SHOULD / MAY, current one first and marked "(Current)". Ask it in the same call as question 1; it is ignored if the user picks Drop.

Apply each answer before moving on: rewrite the finding's suggestion to the chosen resolution, fold in any notes, and set the final severity. If an answer leaves the fix ambiguous, ask one short follow-up; otherwise do not re-ask. Read the notes on each answer: answer any question in them before moving on, and if one challenges the finding's premise, explain and re-offer the options. When a resolution makes other findings moot, say so and skip them.

The final output contains only the non-dropped findings, each with its final severity and the **agreed resolution** (the fix to make, or "follow-up issue: <title>"). Recompute the overall status from them (e.g. no MUST left → not blocked on MUST grounds), list follow-up issues in their own section, and end with a one-line tally: fix now / follow-up / dropped, and how many changed severity.

## Output

Print the review to the console with:
- Overall status at the top (ready to merge, needs work, etc.)
- Grouped findings by severity (MUST / SHOULD / MAY)
- Specific line references where applicable
