---
description: Open chained PRs for the stack via gh stack submit — all repos, one repo, or one step — with a hand-written cross-repo reference block per PR. Retargeting after merges is /stack-rebase.
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(cd *), Bash(for *), Write
---

## Context

- Current directory: !`pwd`
- Directory contents: !`ls`
- Arguments: $ARGUMENTS (optional — see modes below)

## Preflight

Run the guard block from `docs/stacked-pr-workflow.md#guard` and stop immediately if it
fails. `gh stack submit` is the only supported mechanism for opening PRs — **never** fall
back to hand-rolled `gh pr create --base <previous step>` chaining, even if the guard
fails. A silent fallback would create PRs `gh stack` doesn't know about and can't sync
later.

## Workspace and manifest resolution

Resolve `MODE`, `WS`, `MANIFEST`, and the `repos()` helper exactly as described in
`docs/stacked-pr-workflow.md#workspace-and-manifest-resolution`. The manifest is read
only when `MODE=multi`; in single-repo mode there is no manifest and no cross-repo
reference block (Step 5 does not apply).

Retargeting PRs after a merge is **not** this command's job — that's `gh stack sync`,
run by `/stack-rebase` (per `docs/stacked-pr-workflow.md#workflow`). This command only
opens PRs.

## Modes

Parse `$ARGUMENTS` to determine the mode:

| Argument | Mode | Behavior |
|----------|------|----------|
| (none) | **all** | Submit every repo that has a stack. In single-repo mode, operate on this repo. |
| `<repo-name>` | **repo** | (Multi-repo only) Submit just that repo's stack. |
| `step<N>` or `<N>` | **step** | Submit only the repos participating in step `N`, across the whole workspace. `gh stack submit` has no per-branch or per-step flag — see Step 1 for what this scoping does and does not restrict. |

There is no `retarget` mode. A stale base after a merge is fixed by `/stack-rebase`
(`gh stack sync`), never by this command.

## Your task

### Step 0: Resolve mode and repo filter

Match `$ARGUMENTS` against `^step([0-9]+)$` or a bare `^[0-9]+$` first — if it matches,
this is **step mode** with that `N`.

Otherwise, if `$ARGUMENTS` is non-empty:
- **Multi-repo mode:** resolve it against `repos()` — exact match first, then substring
  match against subdirectory names, the same convention `/stack-commit` and
  `/stack-status` use in their Step 0. If it resolves, this is **repo mode** for that
  repo. If nothing matches, report the available repos (from `repos()`) and stop.
- **Single-repo mode:** there is no repo-name concept — a non-empty argument that isn't
  `stepN`/`N` is not a recognized mode here. Report the table above and stop.

An empty `$ARGUMENTS` is **all mode**.

### Step 1: Determine target repos

Build the set of repos this run will act on, and for each, get its current
`gh stack view --json` (needed for the preview in Step 2 regardless of mode):

**All mode:**
- Single-repo mode: the current repo.
- Multi-repo mode: every repo from `repos()` where `gh stack view --json` doesn't exit
  `2` (has a stack).

**Repo mode:** just the resolved repo (multi-repo only).

**Step mode:**
- Multi-repo mode: read the repos participating in step `N` via the manifest-read
  snippet in `docs/stacked-pr-workflow.md#manifest-reads`
  (`.steps[] | select(.n==$n) | .branches | keys[]`). If `$MANIFEST` is absent, this
  command cannot resolve step membership across repos — report that and suggest running
  `/stack-status` first (it offers manifest reconstruction), then stop.
- Single-repo mode: there is no manifest; step `N` is the branch at the **1-indexed
  bottom-first position** `N` in `gh stack view --json .branches`, the same rule the
  other stack commands use. If `N` is out of range, report the stack's actual length and
  stop.

**Step mode scopes which repos run, not which branches get touched within them.**
`gh stack submit` takes no branch- or step-selecting flag — it submits a repo's **entire**
local stack in one call. So selecting step `N` only decides which repos are included in
this run; once a repo is included, submitting it may create or update PRs for that
repo's *other* steps too, as a side effect. This is expected, not a bug — flag it to the
user in Step 2's preview and Step 6's summary rather than letting it appear
unexplained.

**For every target repo, guard the "everything already merged" case.** This is
**documented upstream, not locally measured** — unlike the facts in
`docs/gh-stack-json-reference.md`, which were captured live against this environment,
this one comes from the github/gh-stack README's `gh stack submit` section: if every PR
in a stack is already merged, that stack is complete and can't be extended, so `submit`
automatically starts a **new** stack rooted at trunk for the repo's unmerged branches
instead of doing nothing, leaving the merged stack untouched. Concretely: if every entry
in a target repo's `.branches` has `isMerged: true`, drop that repo from the target set
and report it separately as "already fully merged — nothing to submit" rather than
calling submit there.

### Step 2: Preview and confirm

`gh stack submit` is outward-facing (pushes branches, opens/updates real PRs) and not
cleanly reversible. **Before the first `gh stack submit` call, show the user exactly
what will happen and wait for explicit confirmation.** This gate is not optional and has
no flag to skip it, regardless of mode or arguments.

For each target repo, list its unmerged branches (from the `gh stack view --json`
gathered in Step 1) with their current PR status:

```bash
jq -r '.branches[] | select(.isMerged | not) |
  "\(.name): " + (if .pr then (.pr.state // "PR exists, state unknown") else "no PR yet" end)' \
  <<<"$repo_json"
```

Present something like:

```
About to run `gh stack submit --auto --open` in:
  unloading_robot_ws
    08-31-split_gripper_files  — no PR yet
    08-31-gripper_class        — no PR yet
  contoro_utils
    08-31-gripper_types        — PR exists, state OPEN (will be updated)

This will push these branches to origin and open/update PRs on GitHub, marking
them ready for review (not draft). Continue? [y/N]
```

Also list any repos dropped in Step 1 for the "already fully merged" reason, so the user
knows why they're excluded.

**In step mode**, a target repo's branch list here may include branches beyond step `N`
— per Step 1, `gh stack submit` has no per-step flag and submits a repo's whole local
stack. Say so explicitly in the preview (e.g. "note: this repo's stack includes steps
beyond the one you asked for — submitting a repo submits its entire stack") so the user
isn't surprised by PRs opening for steps they didn't name.

**Stop and wait for the user's explicit confirmation before proceeding to Step 3.**

### Step 3: Submit

For each confirmed target repo, in order:

```bash
cd "$WS/$repo"   # multi-repo mode; current directory in single-repo mode
gh stack submit --auto --open
```

Both flags are required, not optional:
- `--auto` skips the interactive editor gh-stack would otherwise open per branch —
  without it, `submit` cannot run non-interactively.
- `--open` marks new **and existing** PRs ready for review. Without it, `--auto` creates
  **drafts** — the environment fact this command is built against — so `--open` is what
  makes this a real, review-ready submit rather than a silent draft pile-up.

If `gh stack submit` fails for a repo, report the failure and stop before moving to the
next repo — do not submit partial state across repos and then silently skip the
cross-repo block for the ones that failed.

### Step 4: Read back what was submitted

After Step 3 completes for a repo, re-run `gh stack view --json` there to read the PR
each branch now has:

```bash
jq -r '.branches[] | "\(.name)|" + (.pr.number // "—" | tostring) + "|" + (.pr.state // "—") + "|" + (.pr.url // "—")' \
  <<<"$repo_json"
```

**Open question, not yet confirmed:** the `pr` object's key names (`number`, `state`,
`url`) are inferred from the `gh-stack` binary's struct tags, per
`docs/gh-stack-json-reference.md`, and have not been observed against a live PR — that
verification is deferred. Every read above uses `//` fallbacks, so a wrong key name
degrades to `"—"` rather than breaking the command; it does **not** self-correct the key
name. If PR numbers/URLs come back as `"—"` even after a successful submit, that is the
signal the inferred keys are wrong and `docs/gh-stack-json-reference.md` needs updating
against real data.

Keep this per-repo, per-branch table in memory — Step 5 needs it, keyed by step number.

### Step 5: Write the cross-repo reference block (multi-repo mode only)

Skip this step entirely in single-repo mode — there is nothing to cross-reference.

**Only after every target repo has completed Step 3** (so every PR that will exist this
run, does): for each step number that has a PR (via the manifest, matched against the
Step 4 table) in **two or more of this run's target repos**, build the block:

```markdown
---
Part of a multi-repo stack:
- unloading_robot_ws: https://github.com/contoroinc/unloading_robot_ws/pull/412
- contoro_utils: https://github.com/contoroinc/contoro_utils/pull/77
```

GitHub's Stack object (what `gh stack submit` creates) is per-repo — it has no concept
of a PR in another repository, so there is no native place to express "these PRs across
repos are the same logical step." The PR body is the only place that link can live, so
it's added by hand after submission rather than by the extension.

For each repo/PR in that step's block:

```bash
gh pr view "$pr_number" --json body -q .body
```

Take that output, append the block below it (a blank line, then the block), and write the
result with the Write tool to a scratch file (e.g. `pr-body-<repo>-<n>.md` in the
scratchpad); then:

```bash
gh pr edit "$pr_number" --body-file <scratch-file>
```

If a repo/PR's `.pr.url` (or `.pr.number`) came back `"—"` in Step 4 (the unconfirmed-key
case above), write that repo's line in the block as
`- <repo>: (PR url unavailable — check \`gh pr view\` manually)` instead of dropping the
line silently, and still write the block to the other repos' PRs whose data resolved
fine.

A step with a PR in only one of this run's target repos gets no block — there is nothing
to cross-reference yet. If a later run submits another repo for that same step, re-run
this command (or `/stack-create-pr step<N>`) to pick up the now-multi-repo block; this
command does not retroactively edit PRs outside the current run's target set.

### Step 6: Summary

Print a table:

```
| Repo | Step | Branch | PR | State | Status |
|------|------|--------|----|-------|--------|
| unloading_robot_ws | 1 | 08-31-split_gripper_files | #412 | OPEN | created |
| unloading_robot_ws | 2 | 08-31-gripper_class        | #413 | OPEN | created |
| contoro_utils      | 2 | 08-31-gripper_types        | #77  | OPEN | updated (already existed) |
```

List repos skipped for "already fully merged" separately, and any step whose cross-repo
block was written or skipped (and why).

**In step mode**, the table naturally includes rows for steps other than `N` whenever a
target repo's stack had them — that's the whole-local-stack side effect from Step 1 and
Step 2, not a mistake in this table. Note it plainly (e.g. "steps beyond N are listed
because submitting a repo submits its whole stack") so it reads as expected rather than
as noise.

## Rules

- Do NOT include `Co-Authored-By` lines — `gh stack submit --auto` generates PR
  titles/bodies itself; this command only appends the cross-repo block afterward.
- NEVER fall back to hand-rolled `gh pr create --base <branch>` chaining if `gh stack` is
  unavailable — stop instead (see Preflight).
- NEVER retarget a PR's base (`gh pr edit --base`) from this command — that's
  `/stack-rebase` (`gh stack sync`), a separate concern with a separate confirmation.
- `gh stack submit` is outward-facing: always preview and get explicit confirmation
  before the first call, in every mode, with no way to skip it (Step 2).
- Always pass both `--auto` and `--open` to `gh stack submit` — `--auto` for
  non-interactive use, `--open` because `--auto` alone creates drafts.
- Never call `gh stack submit` on a repo whose entire stack is already merged (Step 1) —
  it would start a new stack at trunk instead of doing nothing.
- Every read of `.pr` (number, state, url) must tolerate the key being absent or
  differently named, degrading to `"—"` rather than erroring — never assume the key
  names in `docs/gh-stack-json-reference.md` are confirmed.
- Write the cross-repo reference block only after all target repos have submitted, and
  only for steps with PRs in two or more of this run's target repos.
